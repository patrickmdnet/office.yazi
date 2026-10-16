--- @since 25.2.7

local M = {}

-- Give up on a LibreOffice conversion after this many seconds
local CONVERT_TIMEOUT = 60
-- Leftover conversion directories older than this are treated as abandoned
local STALE_OUTPUT_AGE = 10 * 60
-- Cached PDFs older than this are removed
local STALE_PDF_AGE = 7 * 24 * 60 * 60

-- `ya.emit` and `ya.preview_widget` replaced `ya.mgr_emit` and `ya.preview_widgets` in newer Yazi
local emit = ya.emit or ya.mgr_emit

local function preview_widget(job, widget)
	if ya.preview_widget then
		ya.preview_widget(job, widget)
	elseif ya.preview_widgets then
		ya.preview_widgets(job, { widget })
	end
end

local function preview_error(job, err)
	local wrap = ui.Wrap and ui.Wrap.YES or ui.Text.WRAP
	preview_widget(job, ui.Text(tostring(err or "Failed to generate a preview")):area(job.area):wrap(wrap))
end

local function get_safe_username()
	-- Neither `ya.uid()` nor `ya.user_name()` work on windows.
	local username = os.getenv("USERNAME") or os.getenv("USER") or os.getenv("LOGNAME")

	if not username then
		return "fallback_user"
	end

	-- Sanitize
	return username:gsub("[\\/% ]", "_"):lower()
end

local function get_temp_dir()
	local is_windows = ya.target_family() == "windows"

	local temp

	if is_windows then
		temp = os.getenv("TEMP")
			or os.getenv("TMP")
			or "C:\\Windows\\Temp"
	else
		temp = os.getenv("TMPDIR")
			or os.getenv("TMP")
			or "/tmp"
	end

	-- Normalize path separators
	return temp:gsub("\\", "/")
end

local USERNAME = get_safe_username()
local TEMPDIR = get_temp_dir()

local is_hovered = ya.sync(function(_, url)
	local h = cx.active.current.hovered
	return h and tostring(h.url) == url
end)

-- Remove entries of `dir` that haven't been modified for `max_age` seconds
local function sweep(dir, max_age)
	local files = fs.read_dir(Url(dir), {})
	if not files then
		return
	end

	local now = os.time()
	for _, f in ipairs(files) do
		local mtime = f.cha.mtime
		if mtime and now - mtime > max_age then
			fs.remove(f.cha.is_dir and "dir_all" or "file", f.url)
		end
	end
end

local function rename(from, to)
	if fs.rename then
		return fs.rename(from, to)
	end
	return os.rename(tostring(from), tostring(to))
end

-- Like `Command:output()`, but kills the process if it runs longer than `timeout` seconds.
-- Only suitable for commands with small output, as the pipes aren't drained while waiting.
local function output_with_timeout(cmd, timeout)
	local child, err = cmd:spawn()
	if not child then
		return nil, err
	end

	local deadline = os.time() + timeout
	while not child:try_wait() do
		if os.time() > deadline then
			child:start_kill()
			child:wait()
			return nil, Err("timed out after %s seconds", timeout)
		end
		ya.sleep(0.1)
	end

	return child:wait_with_output()
end

function M:peek(job)
	local start, cache = os.clock(), ya.file_cache(job)
	if not cache then
		return
	end

	local ok, err, bound = self:preload(job)
	if bound and bound > 0 then
		return emit("peek", { bound - 1, only_if = job.file.url, upper_bound = true })
	elseif not ok or err then
		return preview_error(job, err)
	end

	ya.sleep(math.max(0, rt.preview.image_delay / 1000 + start - os.clock()))
	ya.image_show(cache, job.area)
	preview_widget(job, nil)
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h and h.url == job.file.url then
		local step = ya.clamp(-1, job.units, 1)
		emit("peek", { math.max(0, cx.active.preview.skip + step), only_if = job.file.url })
	end
end

function M:doc2pdf(job)
	local cache_home = os.getenv("XDG_CACHE_HOME")
	if not cache_home or cache_home == "" then
		local home = os.getenv("HOME")
		cache_home = home and (home .. "/.cache") or TEMPDIR
	end
	-- Use one Yazi-only LibreOffice profile so conversions cannot attach to the
	-- desktop session, while still letting LibreOffice serialize concurrent
	-- requests through one instance. Keep output unique to avoid same-basename
	-- collisions (such as report.odt and report.ods).
	local root = cache_home .. "/yazi-office-" .. USERNAME .. "/" .. ya.hash("office.yazi") .. "/"
	local pdfdir = root .. "pdf/"
	local outroot = root .. "output/"

	-- Converting is the slow part, so keep the PDF around for every page of the
	-- document, and convert again only when the file changes.
	local cha = job.file.cha
	local key = string.format("%s//%s//%s", tostring(job.file.url), cha.mtime or "", cha.len or "")
	local pdf = pdfdir .. ya.hash(key) .. ".pdf"
	if fs.cha(Url(pdf)) then
		return pdf
	end

	-- Clean up after conversions that were interrupted, and old PDFs (including
	-- those of files that have since changed), which are regenerated on demand.
	sweep(outroot, STALE_OUTPUT_AGE)
	sweep(pdfdir, STALE_PDF_AGE)

	local outdir = outroot .. ya.hash(tostring(job.file.url) .. tostring({})) .. "/"
	local profile = root .. "profile/"
	fs.create("dir_all", Url(outdir))
	fs.create("dir_all", Url(profile))
	fs.create("dir_all", Url(pdfdir))

	-- LibreOffice expects UserInstallation to be a URL, not a filesystem path
	-- windows path starts with drive letter so need extra slash
	local file_url_prefix = ya.target_family() == "windows" and "file:///" or "file://"
	-- do not escape the colon on windows (for C:)
	local regex = ya.target_family() == "windows" and "([^%w%-%._~/:])" or "([^%w%-%._~/])"
	local profile_url = file_url_prefix .. profile:gsub(regex, function(c)
		return string.format("%%%02X", string.byte(c))
	end)

	--[[	For Future Reference: Regarding `libreoffice` as preconverter
	  1. It prints errors to stdout (always, doesn't matter if it succeeded or it failed)
	  2. Always writes the converted files to the filesystem, so no "Mario|Bros|Piping|Magic" for the data stream (https://ask.libreoffice.org/t/using-convert-to-output-to-stdout/38753)
	  3. Plain `pdf` lets LibreOffice choose the correct export filter for the input file type. --]]
	local executable = ya.target_family() == "windows"
		and "soffice.com"
		or "libreoffice"

	local libreoffice, err = output_with_timeout(
		Command(executable)
			:arg({
				"-env:UserInstallation=" .. profile_url,
				"--headless",
				"--norestore",
				"--nodefault",
				"--convert-to",
				"pdf",
				"--outdir",
				outdir,
				tostring(job.file.url),
			})
			:stdin(Command.NULL)
			:stdout(Command.PIPED)
			:stderr(Command.PIPED),
		CONVERT_TIMEOUT
	)

	if not libreoffice then
		fs.remove("dir_all", Url(outdir))
		return nil, Err("Failed to run `%s`: %s", executable, err)
	elseif not libreoffice.status.success then
		local output = libreoffice.stdout .. libreoffice.stderr
		local version = (output:match("LibreOffice .+") or ""):gsub("%\n.*", "")
		local error = (output:match("Error:? .+") or ""):gsub("%\n.*", "")
		if version ~= "" or error ~= "" then
			ya.err((version ~= "" and version or "LibreOffice") .. " " .. (error ~= "" and error or "Unknown error"))
		end
		fs.remove("dir_all", Url(outdir))
		return nil, Err("Failed to preconvert `%s` to a temporary PDF", job.file.name)
	end

	-- The output directory is unique to this conversion, so whatever PDF is in
	-- it is ours, however LibreOffice decided to name it.
	local converted
	for _, f in ipairs(fs.read_dir(Url(outdir), {}) or {}) do
		if f.name:lower():match("%.pdf$") then
			converted = f.url
			break
		end
	end
	if not converted then
		fs.remove("dir_all", Url(outdir))
		return nil, Err("LibreOffice did not produce a PDF for `%s`", job.file.name)
	end

	-- Another conversion of the same file may have finished first, in which case its PDF is just as good
	local moved = rename(converted, Url(pdf))
	fs.remove("dir_all", Url(outdir))
	if not moved and not fs.cha(Url(pdf)) then
		return nil, Err("Failed to move the converted PDF to `%s`", pdf)
	end

	return pdf
end

function M:preload(job)
	-- Yazi invokes preloaders for every matching file on the visible page. Only
	-- convert the hovered file, even when office is accidentally configured as a
	-- preloader, to avoid a burst of LibreOffice processes.
	if not is_hovered(tostring(job.file.url)) then
		return true
	end

	local cache = ya.file_cache(job)
	if not cache or fs.cha(cache) then
		return true
	end

	local pdf, err = self:doc2pdf(job)
	if not pdf then
		return true, err
	end

	local page = job.skip + 1
	local output, err = Command("pdftoppm")
		:arg({
			"-f",
			page,
			"-l",
			page,
			"-singlefile",
			"-jpeg",
			"-jpegopt",
			"quality=" .. rt.preview.image_quality,
			-- Scale the longest side to the preview size, rather than rendering at 150 DPI
			"-scale-to",
			math.max(rt.preview.max_width, rt.preview.max_height),
			pdf,
		})
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output then
		return true, Err("Failed to start `pdftoppm`, error: %s", err)
	elseif not output.status.success then
		-- Scrolled past the last page: report the page count so `peek` can step back to it
		local pages = job.skip > 0 and tonumber(output.stderr:match("the last page %((%d+)%)"))
		return true, Err("Failed to convert page %s of `%s` to an image, stderr: %s", page, job.file.name, output.stderr), pages
	end

	return fs.write(cache, output.stdout)
end

return M
