# FileAss

**An easy way to add file associations to Lazarus applications.**

Drop `TFileAssMan` on a form, add your document types in the Object Inspector,
and register them with an explicit method call. Extensions, descriptions,
custom icons, and launch arguments are configured in the Object Inspector.

The same component and application code work on Windows and Linux. Installer
resources use the same settings as runtime registration. Free Pascal console
applications can also use the library.

## Install in Lazarus

1. Choose **Package → Open Package File (.lpk)**, open
   `component/fileass_runtime.lpk`, and click **Compile**.
2. Open `component/fileass_design.lpk`. Click **Use → Install**, then
   allow Lazarus to rebuild and restart.
3. Find `TFileAssMan` on the **FileAss** component palette.

Select the design package for installation; Lazarus includes its runtime
dependency automatically. The design package adds the palette entry and
component editor. Applications use the runtime package without depending
on the IDE's editor units. Keep both packages
in their original directory structure.

## Get started

Drop `TFileAssMan` onto a form and set these properties in the Object Inspector:

| Component property | What to set |
|---|---|
| `ApplicationID` | Required, stable reverse-domain ID, such as `org.example.notepad`. Use your own ID and keep it unchanged between releases. |
| `ApplicationName` | Required application name shown to users, such as `My Notepad`. |
| `ApplicationDescription` | Optional short description of your application. |
| `ExecutablePath` | Leave blank to use the running application's executable. For design-time preview or installer generation, set the absolute path of the executable being deployed. |
| `RegistrationScope` | Keep `fasCurrentUser` for normal use. `fasAllUsers` requires elevated permissions on Windows; Linux requires system-package deployment. |
| `FileTypes` | Open the collection editor and add one item per extension. |
| `OnError` | Optional event for reporting failed operations. Methods also return a result. |

For each item in **FileTypes**, configure:

| File type property | What to set |
|---|---|
| `Enabled` | Leave `True` to include this item. `False` excludes it from registration and generation. |
| `Extension` | Required extension, such as `.mynote`. A missing leading dot is added automatically. |
| `Description` | Friendly document name, such as `My Notepad document`. |
| `MimeType` | Required on Linux, such as `application/x-my-notepad`. |
| `TypeIdentifier` | Required on macOS, such as `org.example.notepad.document`. |
| `WindowsIcon` | Optional `.ico` path, such as `icons/note.ico`, or a Windows icon resource reference. |
| `LinuxIcon` | Optional SVG or 128-pixel PNG path, such as `icons/note.svg`, or an installed icon-theme name. |
| `MacIcon` | Optional icon filename in the application's bundle Resources directory, such as `note.icns`. |
| `Role` | macOS document role: `farEditor` (default), `farViewer`, or `farNone`. |
| `OpenArguments` | Optional fixed arguments placed before the filename, such as `--`. Do not add `%1` or `%f`; FileAss adds the filename. Linux items must use the same arguments. |

Set both Windows and Linux icon properties for a shared configuration.
Relative icon paths are resolved beside the application's executable; include
those files when distributing your application. These settings are saved in
the form's `.lfm` file.

Call `RegisterAll` from an explicit install action, such as a button click.
Declare `Outcome` as `TFileAssResult` from the `FATypes` unit:

```pascal
Outcome := FileAssMan1.RegisterAll;
if not Outcome.Succeeded then
  ShowMessage(Outcome.Message);
```

Use `UnregisterAll` to remove your application's registrations. Registration
never happens at startup and never replaces a user's chosen default program.

## Try the demo

Open **[demo/FileAssDemo.lpi](demo/FileAssDemo.lpi)**. Its real form resource
contains two file types with custom icons. Buttons let you register, remove,
refresh the system file-type browser, and generate deployment files. Sample
documents check filenames with spaces and Unicode characters.

## Platforms

| Platform | Status |
|---|---|
| Linux | Current-user XDG registration, icons, inspection, removal, and deployment generation tested on Linux Mint Cinnamon. |
| Windows | Native registry backend and the same GUI demo pass smoke tests under Wine. Testing on real Windows is still needed. |
| macOS | Bundle metadata generation and conservative XML plist merging implemented. **Mac testers wanted** for packaging, Finder icons, and document opening. |

macOS support is an initial implementation that needs testing on a real Mac.
Runtime registration reports that application-bundle deployment is required.

## License

[0BSD](LICENSE). Copyright (c) 2026 Tony Stone.
