## Disable Chrome auto-updates
```console
defaults write com.google.Keystone.Agent checkInterval 0
```

## Disable Firefox auto-updates
```console
sudo defaults write /Library/Preferences/org.mozilla.firefox EnterprisePoliciesEnabled -bool TRUE
sudo defaults write /Library/Preferences/org.mozilla.firefox DisableAppUpdate -bool TRUE
```
## Shrink menu bar items
```console
defaults -currentHost write -globalDomain NSStatusItemSpacing -int 8
```

## Disable Caps Lock keyboard layout switch delay
```console
hidutil property --set '{"CapsLockDelayOverride":0}'
```

## Sublime text settings
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

## Brave browser debloat

### ИИ-помощник Leo
```console
defaults write com.brave.Browser BraveAIChatEnabled -bool false
```

### VPN
```console
defaults write com.brave.Browser BraveVPNDisabled -bool true
```

### Rewards и криптокошелёк
```console
defaults write com.brave.Browser BraveRewardsDisabled -bool true
defaults write com.brave.Browser BraveWalletDisabled -bool true
```

### Новости и видеозвонки
```console
defaults write com.brave.Browser BraveNewsDisabled -bool true
defaults write com.brave.Browser BraveTalkDisabled -bool true
```

### Дополнительные функции
```console
defaults write com.brave.Browser BravePlaylistEnabled -bool false
defaults write com.brave.Browser BraveSpeedreaderEnabled -bool false
defaults write com.brave.Browser BraveWaybackMachineEnabled -bool false
defaults write com.brave.Browser TorDisabled -bool true
```

### Аналитика и сбор статистики использования
```console
defaults write com.brave.Browser BraveP3AEnabled -bool false
defaults write com.brave.Browser BraveStatsPingEnabled -bool false
defaults write com.brave.Browser BraveWebDiscoveryEnabled -bool false
```