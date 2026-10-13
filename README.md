# FileAss

### File associations and single-instance apps. Drop, configure, done.

Two nonvisual components for **Free Pascal / Lazarus** that take care of
operating-system file associations and keeping one copy of your app running.
Most setup happens in the **Object Inspector**, with the same application
code on **Windows and Linux**.

### 📄 Give your files an application

Drop **`TFileAssMan`** on a form, set your application name and ID, then add
extensions and document icons to its **FileTypes** collection. Register or
remove them with one call from your application's install action:

```pascal
FileAssMan1.RegisterAll;
// When removing the associations:
FileAssMan1.UnregisterAll;
```

Registration is explicit and preserves the user's chosen default apps.
[Configuration and registration →](GUIDE.md#configure-in-the-object-inspector)

### ⭐ One application instance, without writing IPC code

Drop **`TFileAssInstance`** on your main form, set its **ApplicationID**
(or link it to `TFileAssMan`), and set **Enabled = True**. That's the component
setup for single-instance enforcement—no event handler required.

Want files opened in the existing window? Select **fimForwardParameters**
and assign **OnParameters**. The component queues requests during startup
and delivers them when your application is ready.
[Forwarding, readiness, and events →](GUIDE.md#single-instance-applications)

### Try it in Lazarus

[Install the package →](GUIDE.md#install-in-lazarus), then open
**[demo/FileAssDemo.lpi](demo/FileAssDemo.lpi)**. Register the sample types,
click a document icon to find its file, and open more files into the same
running instance. The demo includes a real `.lfm` with the component settings.

<img src="demo/icons/blue-note.png" width="48" alt="Blue Note document icon"> <img src="demo/icons/amber-sketch.png" width="48" alt="Amber Sketch document icon">

### 🛠️ More when you need it

[Installer exports](GUIDE.md#export-association-files-for-an-installer),
[application-menu launchers and icons](GUIDE.md#application-launchers-and-icons),
and [console applications](GUIDE.md#console-applications) use the same core.
The [developer guide](GUIDE.md) covers setup, properties, and platform details.
Property explanations are also available right in the Object Inspector.

**Linux:** tested on Mint Cinnamon. **Windows:** smoke-tested under Wine;
real Windows testers welcome. **macOS:** tested on Sequoia 15 (Intel, in a
virtual machine) with Lazarus 4.8 and FPC 3.2.4 - the `Info.plist` export,
the single-instance handoff, and documents macOS opens with the program
arriving in the running copy. Clicking through Finder by hand, and how the
document icons look there, have not been checked yet.

![The demo on macOS](images/macos/demo.png)

**[0BSD licensed](LICENSE)** · Free to use in your applications.

Copyright (c) 2026 Tony Stone.
