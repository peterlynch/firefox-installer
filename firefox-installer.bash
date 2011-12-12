#!/bin/bash -x

# Creates an isolated Firefox profile per version and links a versioned Firefox.app file with it
# based on steps found at http://blog.jerodsanto.net/2011/03/install-firefox-4-and-firefox-3-side-by-side-on-mac-os-x/
# Prerequisites
# - OSX
# - a firefox profile directory (template) from which to base a new profile on
# - GNU sed, not the crappy one that comes with OSX - 'sudo port install gsed'
# - iconv for converting UTF-16 encoded file


# exit script if you try to use an uninitialised variable
set -u
# exit script if any statement returns non-true return value
set -e

#VERSION=8.0.1
VERSION=$1
APP_NAME=Firefox-${VERSION}.app


# ==================================
# Step 1: get DMG and extract App bundle: download, mount, copy app, and unmount
echo "Downloading Firefox ${VERSION} ..."
if [ ! -d /Applications/Firefox-${VERSION}.app ]; then
    if [ ! -f "Firefox ${VERSION}.dmg" ]; then
    wget "http://download.mozilla.org/?product=firefox-${VERSION}&os=osx&lang=en-US"    
    fi
    
    if [ -d /Volumes/Firefox ]; then
        # unmount in case some other version
        hdiutil detach /Volumes/Firefox
    fi
    
    open "Firefox ${VERSION}.dmg"
    # wait until mounted
    while [ ! -s /Volumes/Firefox/Firefox.app ]
      do
      printf "%1s \r" waiting to mount disk
    done
    echo "copying /Volumes/Firefox/Firefox.app to /Applications/${APP_NAME}"
    cp -r /Volumes/Firefox/Firefox.app /Applications/${APP_NAME}
    # cleanup
    hdiutil detach /Volumes/Firefox
fi

# ==============================================
# Step 2 create a firefox profile to use with it
#/Applications/Firefox-${VERSION}.app/Contents/MacOS/firefox-bin -ProfileManager
#PROFILE_TARGET="${HOME}/Library/Application Support/Firefox/Profiles/custom.firefox${VERSION}"
if [[ -d "${HOME}/Library/Application Support/Firefox/Profiles/custom.firefox${VERSION}" ]]; then
    echo "target Firefox profile directory already exists - skipping creating a new one"
else
    if [[ ! -d "${HOME}/Library/Application Support/Firefox/Profiles/custom.template" ]]; then
        echo "template Firefox profile does not exist - please create it first and run this script again";
        exit 1
    fi

    echo "Creating a custom Firefox ${VERSION} profile directory..."
    # copy from template - this is up to you...
    eval cp -r "${HOME}/Library/Application\ Support/Firefox/Profiles/custom.template" "${HOME}/Library/Application\ Support/Firefox/Profiles/custom.firefox${VERSION}"
    
    # fix references to old template location
    gsed -i "s/custom.template/custom.firefox${VERSION}/g" "${HOME}/Library/Application Support/Firefox/Profiles/custom.firefox${VERSION}/prefs.js";
    
    
fi

# ===================================================
echo "Updating profiles.ini to reference new profile directory.."
# update Firefox profiles.ini to include your new profile
PROFILES_INI="${HOME}/Library/Application Support/Firefox/profiles.ini"
if [[ `fgrep "Path=Profiles/custom.firefox${VERSION}" "${HOME}/Library/Application Support/Firefox/profiles.ini"` ]] ; then
    echo "WARNING: Profile already added to profiles.ini. Not adding it again";
else
    
    PROFILE_COUNT=`grep '\[Profile' "${PROFILES_INI}" | wc -l`;
    # strip leading spaces
    PROFILE_COUNT=${PROFILE_COUNT##* }
    echo >> "${PROFILES_INI}"
    echo "[Profile${PROFILE_COUNT}]" >> "${PROFILES_INI}"
    echo "Name=custom.firefox${VERSION}" >> "${PROFILES_INI}"
    echo "IsRelative=1" >> "${PROFILES_INI}"
    echo "Path=Profiles/custom.firefox${VERSION}" >> "${PROFILES_INI}"
fi
    
# =================================
# Step 3 Update Firefox app bundle to use a script wrapper specifying our new profile
echo "Changing the way the Firefox app bundle starts up so that it references our custom profile..."
BIN_TARGET="/Applications/${APP_NAME}/Contents/MacOS/firefox-custom-profile.sh"
echo "#!/bin/sh" > ${BIN_TARGET}
echo "MYDIR=\`dirname \"\$0\"\`" >> ${BIN_TARGET}
echo "cd \"\${MYDIR}\"" >> ${BIN_TARGET}
echo "./firefox-bin -P \"custom.firefox${VERSION}\" \"\$@\"" >> ${BIN_TARGET}
chmod +x ${BIN_TARGET}

# =================================
# Step 4, update plist to reference our new executable
FIREFOX_PLIST="/Applications/${APP_NAME}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable firefox-custom-profile.sh" ${FIREFOX_PLIST}
# make a better menu bar name, sed does not like UTF-16, so first convert InfoPlist.strings file to UTF-8
cp /Applications/${APP_NAME}/Contents/Resources/en.lproj/InfoPlist.strings /Applications/${APP_NAME}/Contents/Resources/en.lproj/InfoPlist.strings.ORIGINAL
iconv -f utf-16 -t utf-8 /Applications/${APP_NAME}/Contents/Resources/en.lproj/InfoPlist.strings.ORIGINAL > /Applications/${APP_NAME}/Contents/Resources/en.lproj/InfoPlist.strings
gsed -i "s/Firefox/Firefox ${VERSION}/g" "/Applications/${APP_NAME}/Contents/Resources/en.lproj/InfoPlist.strings";


# =================================
# Step 5, rebuilding launch services database to pick up changes
echo "Rebuilding Launch services database to pick up changes..."
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -kill -r -domain local -domain system -domain user

echo "Done!"

