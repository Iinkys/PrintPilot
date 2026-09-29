# PrintPilot
Quickly disable, restore, and manage print() statements across your Roblox Studio project.


# 🛠️ Debug Print Manager

A Roblox Studio plugin for quickly managing `print()` statements across your entire place or only the objects you've selected.

Built for developers who want an easy way to temporarily disable debug prints without permanently deleting them, while still being able to restore them later.

---

# 🎯 What This Plugin Does

**Disable All**

Disables eligible standalone `print()` statements across the entire place.

**Restore All**

Restores only the print statements previously disabled by this plugin.

**Disable Selected**

Disables eligible print statements only inside the currently selected objects.

**Restore Selected**

Restores plugin-disabled print statements only inside the current selection.

**Enable Only Selected**

Restores plugin-disabled prints in the current selection and disables them everywhere else.

**Ignore Packages**

Optionally skips scripts contained inside Roblox packages.

This setting is saved and persists between Studio sessions.

**Statistics**

Shows statistics for the entire place and the current Studio selection, including scripts scanned, scripts containing prints, active prints, disabled prints, and ignored package scripts.

**Dockable UI**

All controls are contained inside a Roblox Studio `DockWidgetPluginGui`.

---

# 🧠 How It Works

The plugin does not permanently delete your debug prints.

Disabled print statements are marked with:

```lua
-- [DEBUG_PRINT_MANAGER_DISABLED]
```

This allows the plugin to identify exactly which lines it changed and restore only those changes later.

The plugin uses Roblox Studio's `ScriptEditorService` to read and update script source.

---

# 🚨 Important

This plugin is intended to be used in **Roblox Studio Edit Mode**.

Always make sure you understand which scripts are being modified before using place-wide operations.

It is recommended to save your place before performing large-scale source changes.

---

# 📦 Installation

Install the plugin into Roblox Studio and open the **Plugins** tab.

The plugin creates a **Debug Print Manager** toolbar button.

Click the button to open the plugin window.

---

# 🔧 Customization

You are free to:

* Study the source code.
* Modify the plugin for your own workflow.
* Add new features.
* Change the UI.
* Improve or rewrite parts of the code.
* Create your own fork.

Any modified version distributed to other people must remain **open source** and must include the source code and this license.

---

# 💰 Commercial Use

This project is **not for sale**.

You may not:

* Sell the original plugin.
* Sell a modified version of the plugin.
* Put the plugin behind a paid download.
* Charge money for access to the plugin or a modified version.
* Use the plugin as part of a paid product while keeping the modified plugin source closed.

If you build something on top of this project and distribute it, your modifications must remain publicly available as source code under the same license.

---

# 📜 Personal Open Source License

Copyright © 2026 **[Your Name / Username]**

Permission is granted, free of charge, to any person obtaining a copy of this software to:

* Use the software for personal or educational purposes.
* Study how the software works.
* Modify the software.
* Create derivative works.
* Share copies of the software.
* Share modified versions of the software.

### Conditions

1. **No selling**

   This software and derivative versions may not be sold, licensed for a fee, or distributed as a paid product.

2. **Source must remain open**

   Any modified or derivative version that is distributed to others must make its complete source code available.

3. **Same license**

   Distributed modifications and derivative works must remain under this license.

4. **Credit**

   The original author and this project must be credited in redistributed or substantially modified versions.

5. **No removal of license**

   The copyright notice and license terms may not be removed from redistributed versions.

6. **Free redistribution**

   You may share the original or modified software freely, provided that the conditions above are followed.

### Example

You may take this plugin, redesign the UI, add new features, fix bugs, and publish your own version.

You may **not** take that modified version, hide the source code, and sell it as a closed-source plugin.

If you distribute your modified version, **your modifications must also be open source**.

---

# ⚠️ Disclaimer

This software is provided **as-is**, without warranty of any kind.

The author is not responsible for damage, data loss, unexpected source-code changes, or other issues resulting from use of the plugin.

Always keep backups of important projects.

---

# 👤 Author

Created by **[Your Name / Username]**

This is an independent personal project and is not affiliated with or endorsed by Roblox Corporation.
