# FileAss developer guide

[Back to the overview](README.md)

- [Install in Lazarus](#install-in-lazarus)
- [Object Inspector configuration](#configure-in-the-object-inspector)
- [Register and remove](#register-and-remove)
- [Export files for an installer](#export-association-files-for-an-installer)
- [Application launchers and icons](#application-launchers-and-icons)
- [Single-instance applications](#single-instance-applications)
- [Console applications](#console-applications)

## Install in Lazarus

1. **Package → Open Package File (.lpk)** → open
   `component/fileass_runtime.lpk` → **Compile**.
2. Open `component/fileass_design.lpk` → **Use → Install**.
3. Allow Lazarus to rebuild and restart. Find `TFileAssMan` and `TFileAssInstance` on the **FileAss** palette.

When updating the component source, rebuild and restart Lazarus too: its
installed components must match the properties saved in your forms.

The design package installs the palette entries and component editor, including
its runtime dependency automatically. Applications use only the runtime
package. Keep the directory structure intact.

## Configure in the Object Inspector

Drop `TFileAssMan` onto a form. Set `ApplicationID` and `ApplicationName`,
then open **FileTypes** and add an item for each extension. For Linux, each
item also needs a `MimeType`.

Property and event descriptions are included in the source. In Lazarus,
right-click the Object Inspector and enable **Show hints** and **Show information
box** (also available in its options). Hover over a property name for help,
or select it to read the explanation below the property list. The same help
is available for items in the **FileTypes** collection.

<details>
<summary><strong>Component properties</strong></summary>

| Property | Setting |
|---|---|
| `ApplicationID` | Required stable ID, e.g. `org.example.notepad`. Use your own ID; keep it unchanged between releases. |
| `ApplicationName` | Required display name, e.g. `My Notepad`. |
| `ApplicationDescription` | Optional short application description. |
| `ExecutablePath` | Blank uses the running executable. Design-time preview and installer generation require the deployed executable's absolute path. |
| `RegistrationScope` | Default: `fasCurrentUser`. `fasAllUsers` requires elevation on Windows or system-package deployment on Linux. |
| `SupportsMultipleFiles` | Default `False`. Set `True` for Linux batch arguments (`%F`) and Windows multi-selection (`MultiSelectModel` `Player`, with shell limits). |
| `ShowInApplicationMenu` | Default `False`. Show the Linux launcher in the Applications menu when registering or exporting. |
| `ClaimDefault` | Default `False`. On Linux, make the program the default for its types in the user's `mimeapps.list` when registering, and report another program there as needing repair. Off leaves the default to the user. |
| `LinuxApplicationIcon` | Launcher icon: SVG/128-pixel PNG path or installed theme name. Relative paths resolve beside the executable. |
| `MacApplicationIcon` | Application icon filename, such as `App.icns`, supplied by the installer in the bundle's `Contents/Resources`. |
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

## Register and remove

Call this from an explicit install action, such as a button click.
Declare `Outcome` as `TFileAssResult` from `FATypes`:

```pascal
Outcome := FileAssMan1.RegisterAll;
if not Outcome.Succeeded then
  ShowMessage(Outcome.Message);
```

`UnregisterAll` takes it all out again. Nothing is registered at startup, and
the user's chosen default application is never replaced.

Everything FileAss installs is named after your `ApplicationID`: the `.desktop`
entry, MIME package and icons on Linux, the ProgIDs and capability keys on
Windows. That is how `UnregisterAll` finds it later, whatever the file types
are by then, and how `RegisterAll` cleans up after a file type you have since
dropped. So keep the ID the same from release to release. On Windows a ProgID
that carries your ID in its name but was not made by FileAss is left alone,
and `RegisterAll` says so.

macOS requires application-bundle deployment rather than runtime registration.

## Export association files for an installer

`RegisterAll` installs associations on the current system. Alternatively,
`GenerateDeploymentFiles` exports files your installer or system package can
install, using the same Object Inspector settings. It does not build an
installer, run an installation script, or change the current associations.

| Platform | Exported files |
|---|---|
| Windows | An application-ID `.reg` file containing extension, document name, icon path, and open-command entries. Referenced icons must be distributed separately. |
| Linux | A `.desktop` application entry, MIME XML defining the file types, and document icon resources when configured with icon files. |
| macOS | `Info.plist` document-type metadata for an application bundle. Tested on macOS 15: a document macOS opens with the program reaches the running copy. |

Each export also includes `manifest.txt`, listing the generated files.
The Linux `.desktop` entry tells the desktop how to launch your application
with files and lists its supported MIME types for **Open With**. It does not
start your application automatically at login.

Set `ExecutablePath` to the intended installed executable before exporting:

```pascal
Outcome := FileAssMan1.GenerateDeploymentFiles(OutputDirectory);
```

The demo's **Export** button demonstrates this using the demo executable's
current location. Export is optional if your application uses runtime
registration instead; the installer decides how to install the exported files.

## Application launchers and icons

On Linux, set **ShowInApplicationMenu = True** and optionally
**LinuxApplicationIcon**, then call `RegisterAll`. This makes the existing
desktop entry visible in the Applications menu. `UnregisterAll` removes the
entry and its icon. The demo's **Add to Applications menu** checkbox
applies this option when you register or export.

Registering writes the types and the launcher and refreshes the desktop's
caches, which is what makes them take effect; the status reports a cache
older than the files, so a repair knows to run the refresh again. Which
program opens a type is the user's choice unless **ClaimDefault = True**,
which also names this program as the default for its own types, the way
`xdg-mime default` does, and reports any other program chosen there as
needing repair. Leave it off for types other programs commonly handle;
turn it on for a type that is the program's own.

Exports use the same settings. A Linux installer can install the generated
`applications/*.desktop` entry and icon resources, and optionally place a copy
of that entry on the user's desktop. FileAss does not place desktop shortcuts
automatically; the desktop may require the user to trust the copied launcher.
These launchers do not enable startup at login.

On macOS, **MacApplicationIcon** adds `CFBundleIconFile` to the exported
`Info.plist`. The installer supplies the `.app` bundle and its icon; FileAss does
not create a bundle or desktop alias. How the icon looks in Finder has not
been checked yet. Windows
exports continue to contain associations; Start-menu and desktop shortcuts are
handled by the Windows installer.

## Single-instance applications

Drop `TFileAssInstance` on the main form, set **Enabled = True**, and either
link its **FileAssMan** property or set its own **ApplicationID**.
The default **fimSingleInstance** mode quietly terminates secondary launches.

For forwarding, choose **fimForwardParameters** and assign **OnParameters**.
Set **FileAssMan.SupportsMultipleFiles = True** if your app accepts batches.
The event receives a parameter list, the sender's working directory, and an
`Initial` flag. Use the same handler for initial and forwarded launches;
relative filenames are relative to the supplied directory.

**AutoReady = True** delivers after normal form creation. For additional
initialization, set it to `False` and set **ReadyForParameters = True** when
ready. Forwarded requests remain queued during initialization.

<details>
<summary><strong>Instance properties and events</strong></summary>

| Property or event | Purpose |
|---|---|
| `Enabled` | Start automatically when the form loads; default `False`. Explicit `Start` is also available. |
| `FileAssMan` | Optional reference supplying the application ID. |
| `ApplicationID` | Stable reverse-domain ID when no FileAssMan is linked. |
| `Mode` | `fimSingleInstance` ignores secondary launches; `fimForwardParameters` queues their parameters. |
| `HandleFileOpenEvents` | Default `True`; route LCL file-open/drop events through the same ready-gated handler. Disable if already handling those events yourself. |
| `AutoReady` | Default `True`. Set `False` for explicit readiness control. |
| `ReadyForParameters` | Gates event delivery without releasing instance ownership. |
| `IncludeInitialParameters` | Default `True`; initial parameters use the same event. |
| `AutoTerminateSecondary` | Default `True`. Set `False` to control secondary shutdown yourself. |
| `OnParameters` | Handle the supplied parameters; copy the list if retaining it after the event. |
| `OnActivateRequested` | A forwarded launch has no parameters. By default the form component restores its owner form. |
| `OnSecondaryInstance` | Runs in the secondary process after ignoring or queuing its launch. |
| `OnError` | Reports failed startup or delivery. Unhandled errors display a dialog in GUI applications. |

`Role` and `LastResult` report startup status. A queued request does not
confirm that the application opened a document. Independent requests may
arrive in a different order; each request preserves its own parameter list.
Callbacks run on the GUI thread. Set readiness to `False` to pause delivery.
If other work runs in `FormCreate`, skip it when `Role <> firPrimary`.

The FCL transport uses temporary files. Instance ownership uses an OS-held
lock released when the process exits, including a crash; a leftover lock
file does not prevent startup. Forwarded requests still in the inbox remain for the next
primary. Windows, Linux and macOS have been tested - on a Mac: slow starts,
fifty launches at once, a killed primary, and documents opened by macOS.

</details>

## Console applications

A program with no forms creates the same classes the components are made of:
**TFileAssManager** from **FACore** for the file types (`TFileAssMan` is that
class on the palette), and **TFileAssInstanceManager** from **FAInstanceCore**
for the single instance. Neither needs the LCL.

For the instance manager: configure its ID, mode, and events, call `Start`, set readiness,
and call `Poll` from the application's loop. `Start` returns `firPrimary`,
`firSecondary`, or `firFailed`; console code decides whether to exit.
[FileAssConsole.lpr](demo/ConsoleExample/FileAssConsole.lpr) demonstrates this:
run `FileAssConsole listen`, then `FileAssConsole -- "a document"` in another
terminal. It also demonstrates association registration without a form.

Thumbnail registration is a possible future option; it is not implemented.

Copyright (c) 2026 Tony Stone.
