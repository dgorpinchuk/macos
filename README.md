# Disable Chrome auto-updates
```console
defaults write com.google.Keystone.Agent checkInterval 0
```

# Disable Firefox auto-updates
```console
sudo defaults write /Library/Preferences/org.mozilla.firefox EnterprisePoliciesEnabled -bool TRUE
sudo defaults write /Library/Preferences/org.mozilla.firefox DisableAppUpdate -bool TRUE
```
