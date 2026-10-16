<div align="center">

# office.yazi
### A plugin to preview office documents in <a href="https://github.com/sxyazi/yazi">Yazi <img src="https://github.com/sxyazi/yazi/blob/main/assets/logo.png?raw=true" alt="a duck" width="24px" height="24px"></a>

<img src="https://github.com/macydnah/office.yazi/blob/assets/preview_test.gif" alt="preview test" width="88%">

##

</div>

## Installation
> [!TIP]
> Installing this plugin with `ya` will conveniently clone the plugin from GitHub,
> copy it to your plugins directory, and update the `package.toml` to lock its version [^1].
> 
> To install it with `ya` run:
> ```sh
> ya pkg add macydnah/office
> ```

> Or if you prefer a manual approach:
> ```sh
> ## For linux and MacOS
> git clone https://github.com/macydnah/office.yazi.git ~/.config/yazi/plugins/office.yazi
> 
> ## For Windows
> git clone https://github.com/macydnah/office.yazi.git %AppData%\yazi\config\plugins\office.yazi
> ```

## Usage
In your `yazi.toml` add previewer rules[^3] to run the `office` plugin with office documents.

Do not configure `office` as a preloader. Yazi runs preloaders concurrently for
all matching files on the visible page, which can start many LibreOffice processes
while browsing a directory. The previewer already generates and caches a preview
for the hovered document.

> [!NOTE]
> Your config may be different depending if you're *appending*, *prepending* or *overriding* default rules.
> If unsure, take a look at [Configuration](https://yazi-rs.github.io/docs/configuration/overview)[^4]
> and [Configuration mixing](https://yazi-rs.github.io/docs/configuration/overview#mixing)[^5]

For a general usecase, you may use the following rules
```toml
[plugin]

prepend_previewers = [
    # Office Documents
    { mime = "application/openxmlformats-officedocument.*", run = "office" },
    { mime = "application/oasis.opendocument.*", run = "office" },
    { mime = "application/ms-excel*", run = "office" },
    { mime = "application/ms-powerpoint*", run = "office" },
    { mime = "application/ms-word*", run = "office" },
    { mime = "application/msword", run = "office" },
    { url = "*.docx", run = "office" },
]
```

> [!WARNING]
> Avoid a catch-all `application/ms-*` rule: it also matches `application/ms-opentype`
> fonts and takes them away from Yazi's built-in font previewer.

### Paging
Scroll the preview (by default <kbd>J</kbd>/<kbd>K</kbd>) to move between pages of a
document. Scrolling past the last page stays on the last page.

### Caching
Converting a document with LibreOffice is the slow part, so the plugin keeps the
converted PDF and only renders each page from it. A document is converted again only
when it changes. Cached PDFs are removed after a week, and folders left behind by
interrupted conversions after 10 minutes.

The cache lives in `$XDG_CACHE_HOME/yazi-office-<user>/`, falling back to
`~/.cache/yazi-office-<user>/`, or the system temp directory if `HOME` isn't set
(the usual case on Windows).

A conversion that takes longer than 60 seconds is cancelled and reported as an error in
the preview.

## Dependencies
> [!IMPORTANT]
> Make sure that these commands are installed in your system and can be found in `PATH`:
>
> - `libreoffice` (`soffice.com` on Windows)
> - `pdftoppm`, from [Poppler](https://poppler.freedesktop.org)

### Windows
- **LibreOffice:** add its `program` folder (usually `C:\Program Files\LibreOffice\program`)
  to `PATH`, so that `soffice.com` can be found.
- **Poppler:** install it, for example with `winget install oschwartz10612.Poppler`, and make sure
  its `Library\bin` folder is in `PATH`.

## Troubleshooting
If the preview stays empty or shows an error, start Yazi with `YAZI_LOG=debug` and check its
log file (`%AppData%\yazi\state\yazi.log` on Windows, `~/.local/state/yazi/yazi.log` elsewhere).
LibreOffice errors are written there.

## License
office.yazi is licensed under the terms of the [MIT License](LICENSE)

[^1]: [The official package manager for Yazi](https://yazi-rs.github.io/docs/cli)
[^2]: [Preloaders rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.preloaders)
[^3]: [Previewers rules](https://yazi-rs.github.io/docs/configuration/yazi#plugin.previewers)
[^4]: [Configuration](https://yazi-rs.github.io/docs/configuration/overview)
[^5]: [Configuration mixing](https://yazi-rs.github.io/docs/configuration/overview#mixing)
