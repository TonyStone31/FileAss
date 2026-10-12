# FileAss

### File associations for Lazarus, without the busywork.

Drop **`TFileAssMan`** on a form, configure your file types in the Object
Inspector, and register them when the user chooses. The same application
code works on **Windows and Linux**.

- 📄 Custom extensions, document icons, and launch arguments.
- 🛠️ Runtime registration and installer resources from the same properties.
- 🧹 Explicit registration and removal, preserving the user's default apps.

### Try it

Open **[demo/FileAssDemo.lpi](demo/FileAssDemo.lpi)** to register two sample
file types, check their status, and open them from your file manager.

<img src="demo/icons/blue-note.png" width="48" alt="Blue Note document icon"> <img src="demo/icons/amber-sketch.png" width="48" alt="Amber Sketch document icon">

**Linux:** tested on Mint Cinnamon. **Windows:** smoke-tested under Wine;
real Windows testing welcome. **Mac testers wanted:** initial bundle metadata
support needs testing for Finder icons and document opening.

**[0BSD licensed](LICENSE)** · Free to use in your applications.

---

## Installation and configuration

### Install in Lazarus

1. **Package → Open Package File (.lpk)** → open
   `component/fileass_runtime.lpk` → **Compile**.
2. Open `component/fileass_design.lpk` → **Use → Install**.
3. Allow Lazarus to rebuild and restart. Find `TFileAssMan` on the **FileAss** palette.

The design package installs the palette entry and component editor, including
its runtime dependency automatically. Applications use only the runtime
package. Keep the directory structure intact.

### Configure in the Object Inspector

Drop `TFileAssMan` onto a form. Set `ApplicationID` and `ApplicationName`,
then open **FileTypes** and add an item for each extension. For Linux, each
item also needs a `MimeType`.

<details>
<summary><strong>Component properties</strong></summary>

| Property | Setting |
|---|---|
| `ApplicationID` | Required stable ID, e.g. `org.example.notepad`. Use your own ID; keep it unchanged between releases. |
| `ApplicationName` | Required display name, e.g. `My Notepad`. |
| `ApplicationDescription` | Optional short application description. |
| `ExecutablePath` | Blank uses the running executable. Design-time preview and installer generation require the deployed executable's absolute path. |
| `RegistrationScope` | Default: `fasCurrentUser`. `fasAllUsers` requires elevation on Windows or system-package deployment on Linux. |
| `FileTypes` | Collection of file extensions and their settings. |
| `OnError` | Optional error event; methods also return a result. |

</details>

<details>
<summary><strong>FileTypes item properties</strong></summary>

| Property | Setting |
|---|---|
| `Enabled` | Default: `True`. Disabled items are excluded from registration and generation. |
| `Extension` | Required, e.g. `.mynote`. A missing leading dot is added. |
| `Description` | Document display name, e.g. `My Notepad document`. |
| `MimeType` | Required on Linux, e.g. `application/x-my-notepad`. |
| `TypeIdentifier` | Required on macOS, e.g. `org.example.notepad.document`. |
| `WindowsIcon` | Optional `.ico` path or Windows icon resource reference. |
| `LinuxIcon` | Optional SVG or 128-pixel PNG path, or installed icon-theme name. |
| `MacIcon` | Optional icon filename in the bundle's Resources directory, e.g. `note.icns`. |
| `Role` | macOS role: `farEditor` (default), `farViewer`, or `farNone`. |
| `OpenArguments` | Optional arguments before the filename, e.g. `--`. FileAss adds the filename; omit `%1` and `%f`. Linux items must use the same arguments. |

</details>

For custom icons on both platforms, set `WindowsIcon` to `icons/note.ico`
and `LinuxIcon` to `icons/note.svg`. Relative paths resolve beside the
executable; distribute those icon files with your application. All settings
are saved in the form's `.lfm`.

### Register and remove

Call this from an explicit install action, such as a button click.
Declare `Outcome` as `TFileAssResult` from `FATypes`:

```pascal
Outcome := FileAssMan1.RegisterAll;
if not Outcome.Succeeded then
  ShowMessage(Outcome.Message);
```

Use `UnregisterAll` to remove owned registrations. Nothing is registered
at startup, and the user's chosen default application is never replaced.
On Windows, registration updates use the saved installed values, and removal
uses the installed inventory even if the collection has changed. Externally
edited values are preserved. Older registrations without an inventory must
first be registered with their unchanged settings, or removed with those
settings before upgrading.

macOS requires application-bundle deployment rather than runtime registration.

Thumbnail registration is a possible future option; it is not implemented.

Copyright (c) 2026 Tony Stone.
