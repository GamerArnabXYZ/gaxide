[app]
title = Git Push API App
package.name = gitpushapi
package.domain = org.gamerarnabxyz
source.dir = .
source.include_exts = py,png,jpg,kv

version = 1.0.0
requirements = python3,kivy,requests,urllib3,chardet,idna

orientation = portrait
fullscreen = 0

# Android specific configurations
android.permissions = INTERNET, WRITE_EXTERNAL_STORAGE, READ_EXTERNAL_STORAGE
android.api = 33
android.minapi = 21
android.archs = armeabi-v7a, arm64-v8a
android.allow_backup = True

[buildozer]
log_level = 2
warn_on_root = 1
