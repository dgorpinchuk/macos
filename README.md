# Disable Chrome auto-updates
```console
defaults write com.google.Keystone.Agent checkInterval 0
```

# Disable Firefox auto-updates
```console
sudo defaults write /Library/Preferences/org.mozilla.firefox EnterprisePoliciesEnabled -bool TRUE
sudo defaults write /Library/Preferences/org.mozilla.firefox DisableAppUpdate -bool TRUE
```

# Sublime text settings
```json
{
  "theme": "Adaptive.sublime-theme",
  "trim_trailing_white_space_on_save": "all",
  "trim_only_modified_white_space": true,
  "ensure_newline_at_eof_on_save": false,
  "highlight_modified_tabs": true,
  "bold_folder_labels": true,
  "adaptive_dividers": true,
  "show_line_endings": true,
  "open_files_in_new_window": "never",
  "console_max_history_lines": 0,
  "font_face": "Menlo",
  "font_size": 13,
  "ignored_packages":
  [
    "Vintage",
  ],
  "index_files": true,
}
```
