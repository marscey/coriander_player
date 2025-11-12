#!/bin/bash

# macOS build script for desktop_lyric component
# This script builds the desktop_lyric component and deploys it to the application directory

echo "======================================="
echo "Desktop Lyric Build Script for macOS"
echo "======================================="

# Parse build mode parameter
BUILD_MODE="debug"
INSTALL_TO_APP=false
SOURCE="auto"

while [[ $# -gt 0 ]]; do
  case $1 in
    -b|--build-mode)
      BUILD_MODE="$2"
      shift 2
      ;;
    -i|--install-to-app)
      INSTALL_TO_APP=true
      shift
      ;;
    --source)
      SOURCE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--build-mode <debug|release>] [--install-to-app] [--source pub_cache|test_dir|auto]"
      exit 1
      ;;
  esac
done

# Determine source based on build mode if auto
if [[ "$SOURCE" == "auto" ]]; then
  if [[ "$BUILD_MODE" == "debug" ]]; then
    SOURCE="test_dir"
  else
    SOURCE="pub_cache"
  fi
fi

echo "Build mode: $BUILD_MODE"
echo "Install to app bundle: $INSTALL_TO_APP"
echo "Source: $SOURCE"

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEST_DESKTOP_LYRIC_DIR="$PROJECT_ROOT/test/desktop_lyric"

# Temp build directory - 直接使用根目录下的build/desktop_lyric
TEMP_BUILD_DIR="$PROJECT_ROOT/build/desktop_lyric"
echo "Using build directory: $TEMP_BUILD_DIR"

# Determine Flutter executable
if command -v flutter &> /dev/null; then
    FLUTTER_CMD="flutter"
else
    echo "Error: flutter command not found. Please ensure Flutter is installed and in your PATH."
    exit 1
fi

# Clean and create temp build directory
rm -rf "$TEMP_BUILD_DIR"
mkdir -p "$TEMP_BUILD_DIR"

# Handle different source options
if [[ "$SOURCE" == "test_dir" ]]; then
  echo "Using source from test directory: $TEST_DESKTOP_LYRIC_DIR"
  
  # Check if test directory exists
  if [ -d "$TEST_DESKTOP_LYRIC_DIR" ]; then
    echo "Copying desktop_lyric source code from test directory..."
    cp -r "$TEST_DESKTOP_LYRIC_DIR"/* "$TEMP_BUILD_DIR/"
  else
    echo "Warning: Test directory not found: $TEST_DESKTOP_LYRIC_DIR"
    echo "Falling back to Pub cache source..."
    SOURCE="pub_cache"
  fi
fi

# Handle Pub cache source (default or fallback)
if [[ "$SOURCE" == "pub_cache" ]]; then
  # Find desktop_lyric in Pub cache
  # First check hosted packages, then git packages
  echo "Searching for desktop_lyric in Pub cache..."
  
  DESKTOP_LYRIC_PATH=""
  PUB_CACHE_GIT="$HOME/.pub-cache/git"
  
  # Try to extract ref from pubspec.yaml first
  PUB_SPEC_PATH="$PROJECT_ROOT/pubspec.yaml"
  REF_VALUE=""
  
  if [ -f "$PUB_SPEC_PATH" ]; then
    echo "Checking for ref in pubspec.yaml..."
    # Extract ref value specifically for desktop_lyric dependency
    # First, print the relevant section for debugging
    echo "Extracting desktop_lyric dependency section from pubspec.yaml..."
    
    # Use a more robust approach to extract the ref value
    # This will find the line with 'desktop_lyric:' and then find the next 'ref:' line
    REF_LINE=$(grep -A 10 'desktop_lyric:' "$PUB_SPEC_PATH" | grep -m 1 '^\s*ref:\s*')
    
    echo "Raw ref line: '$REF_LINE'"
    
    if [ ! -z "$REF_LINE" ]; then
        # Use a simpler approach to extract only the commit hash
        # Split the line by spaces and take the last part which should be the commit hash
        REF_VALUE=$(echo "$REF_LINE" | awk '{print $NF}')
        
        echo "Found ref value for desktop_lyric: '$REF_VALUE'"
      
      # Try to find git directory with matching ref
      if [ -d "$PUB_CACHE_GIT" ]; then
        echo "Searching in git cache: $PUB_CACHE_GIT"
        # Look for directories containing desktop_lyric and the ref value
        echo "Available desktop_lyric directories in git cache:"
        ls -d "$PUB_CACHE_GIT"/*desktop_lyric* 2>/dev/null || echo "None found"
        
        for dir in "$PUB_CACHE_GIT"/*desktop_lyric*; do
          if [ -d "$dir" ]; then
            # Get the directory name which often contains the ref
            dir_name=$(basename "$dir")
            echo "Checking directory: $dir_name"
            if [[ "$dir_name" == *"$REF_VALUE"* ]]; then
              echo "Found desktop_lyric git directory with matching ref: $dir"
              DESKTOP_LYRIC_PATH="$dir"
              break
            else
              echo "  Ref '$REF_VALUE' not found in directory name"
            fi
          fi
        done
      else
        echo "Git cache directory not found: $PUB_CACHE_GIT"
      fi
    else
      echo "No ref line found for desktop_lyric dependency in pubspec.yaml"
    fi
    
    # If ref was found but directory not found, output a warning
    if [ ! -z "$REF_VALUE" ] && [ -z "$DESKTOP_LYRIC_PATH" ]; then
      echo "Warning: Ref value '$REF_VALUE' found but matching directory not found in git cache"
    fi
  else
    echo "pubspec.yaml not found at: $PUB_SPEC_PATH"
  fi
  
  # If not found using ref, try hosted packages
  if [ -z "$DESKTOP_LYRIC_PATH" ]; then
    echo "Trying to find desktop_lyric in hosted packages..."
    PUB_CACHE_HOSTED="$HOME/.pub-cache/hosted"
    
    if [ -d "$PUB_CACHE_HOSTED" ]; then
      for repo in "$PUB_CACHE_HOSTED"/*; do
        if [ -d "$repo" ]; then
          LYRIC_PATH="$repo/desktop_lyric-*"
          if compgen -G "$LYRIC_PATH" > /dev/null; then
            # Select the latest version
            DESKTOP_LYRIC_PATH="$(ls -d $LYRIC_PATH | sort -V | tail -n 1)"
            echo "Found desktop_lyric hosted package: $DESKTOP_LYRIC_PATH"
            break
          fi
        fi
      done
    fi
  fi
  
  # If still not found, try git packages without ref constraint
  if [ -z "$DESKTOP_LYRIC_PATH" ]; then
    echo "Trying to find desktop_lyric in git packages without ref constraint..."
    if [ -d "$PUB_CACHE_GIT" ]; then
      for dir in "$PUB_CACHE_GIT"/*desktop_lyric*; do
        if [ -d "$dir" ]; then
          echo "Found desktop_lyric git directory: $dir"
          DESKTOP_LYRIC_PATH="$dir"
          break
        fi
      done
    fi
  fi
  
  if [ -z "$DESKTOP_LYRIC_PATH" ]; then
    echo "Error: desktop_lyric not found in Pub cache."
    echo "Please run 'flutter pub get' in the project root first."
    exit 1
  fi
  
  # Copy source code from cache to build directory
  echo "Copying desktop_lyric source code from Pub cache to build directory..."
  cp -r "$DESKTOP_LYRIC_PATH"/* "$TEMP_BUILD_DIR/"
fi

# Ensure the copied directory has proper structure
if [ ! -f "$TEMP_BUILD_DIR/pubspec.yaml" ]; then
  echo "Error: pubspec.yaml not found in the copied source code."
  exit 1
fi

# 进入构建目录并获取依赖
cd "$TEMP_BUILD_DIR"
echo "Getting Flutter packages..."
$FLUTTER_CMD pub get

# 初始化macOS支持（如果不存在）
if [ ! -d "macos" ]; then
  echo "Initializing macOS support..."
  $FLUTTER_CMD create --platforms=macos .
fi

# 构建参数
BUILD_TYPE="--release"
if [ "$BUILD_MODE" = "debug" ]; then
    BUILD_TYPE="--debug"
    echo "Using debug build mode"
else
    echo "Using release build mode"
fi

# 执行构建
echo "Building desktop_lyric for macOS ($BUILD_MODE)..."
$FLUTTER_CMD clean
$FLUTTER_CMD build macos $BUILD_TYPE
BUILD_SUCCESS=$?

# 直接使用构建产物目录作为中间目录，无需额外复制
# 确定构建输出路径
if [ "$BUILD_MODE" = "debug" ]; then
    # 尝试先在Debug目录查找，如果找不到则在Release目录查找
    if [ -d "$TEMP_BUILD_DIR/build/macos/Build/Products/Debug/desktop_lyric.app" ]; then
        # 使用构建产物目录作为中间目录
        DESKTOP_LYRIC_TARGET_DIR="$TEMP_BUILD_DIR/build/macos/Build/Products/Debug"
        BUILD_OUTPUT_PATH="$DESKTOP_LYRIC_TARGET_DIR/desktop_lyric.app"
    elif [ -d "$TEMP_BUILD_DIR/build/macos/Build/Products/Release/desktop_lyric.app" ]; then
        # 使用构建产物目录作为中间目录
        DESKTOP_LYRIC_TARGET_DIR="$TEMP_BUILD_DIR/build/macos/Build/Products/Release"
        BUILD_OUTPUT_PATH="$DESKTOP_LYRIC_TARGET_DIR/desktop_lyric.app"
        echo "⚠️ Warning: Using Release build for Debug mode"
    else
        BUILD_OUTPUT_PATH=""
    fi
else
    # 使用构建产物目录作为中间目录
    DESKTOP_LYRIC_TARGET_DIR="$TEMP_BUILD_DIR/build/macos/Build/Products/Release"
    BUILD_OUTPUT_PATH="$DESKTOP_LYRIC_TARGET_DIR/desktop_lyric.app"
fi

# 确保构建成功，如果失败则报错退出
if [ $BUILD_SUCCESS -ne 0 ] || [ ! -d "$BUILD_OUTPUT_PATH" ]; then
    echo "❌ Build failed or output not found: $BUILD_OUTPUT_PATH"
    echo "Please check the build errors above."
    exit 1
fi

# 构建成功，确保可执行文件有执行权限
chmod +x "$BUILD_OUTPUT_PATH/Contents/MacOS/desktop_lyric"

# 对应用包进行自签名
codesign --force --deep --sign - "$BUILD_OUTPUT_PATH" > /dev/null 2>&1 || true

echo "✅ Build successful!"
echo "Using build artifacts directly from: $BUILD_OUTPUT_PATH"
echo "Executable size: $(ls -la "$BUILD_OUTPUT_PATH/Contents/MacOS/desktop_lyric" | awk '{print $5}') bytes"

# 安装到应用包
if [ "$INSTALL_TO_APP" = true ]; then
    # 确定应用包路径
    if [ "$BUILD_MODE" = "debug" ]; then
        APP_BUNDLE_PATH="$PROJECT_ROOT/build/macos/Build/Products/Debug/Coriander Player.app"
    else
        APP_BUNDLE_PATH="$PROJECT_ROOT/build/macos/Build/Products/Release/Coriander Player.app"
    fi
    
    APP_FRAMEWORKS_DIR="$APP_BUNDLE_PATH/Contents/Frameworks"
    
    if [ -d "$APP_BUNDLE_PATH" ]; then
        echo "Installing desktop_lyric to app bundle: $APP_BUNDLE_PATH"
        
        # 创建目标目录
        mkdir -p "$APP_FRAMEWORKS_DIR/desktop_lyric"
        
        # 直接从构建产物目录复制到应用包（不再通过中间目录）
        rm -rf "$APP_FRAMEWORKS_DIR/desktop_lyric/desktop_lyric.app"
        cp -R "$BUILD_OUTPUT_PATH" "$APP_FRAMEWORKS_DIR/desktop_lyric/"
        
        # 设置权限并签名
        chmod +x "$APP_FRAMEWORKS_DIR/desktop_lyric/desktop_lyric.app/Contents/MacOS/desktop_lyric"
        codesign --force --deep --sign - "$APP_FRAMEWORKS_DIR/desktop_lyric/desktop_lyric.app" > /dev/null 2>&1 || true
        
        echo "✅ Desktop lyric installed to app bundle successfully!"
        echo "Installed file size: $(ls -la "$APP_FRAMEWORKS_DIR/desktop_lyric/desktop_lyric.app/Contents/MacOS/desktop_lyric" | awk '{print $5}') bytes"
    else
        echo "Warning: App bundle not found at $APP_BUNDLE_PATH. Please build the app first."
    fi
fi

echo ""
echo "✅ Desktop lyric component deployment completed!"
echo "Build mode: $BUILD_MODE"
echo "Location: $BUILD_OUTPUT_PATH"
echo "Executable size: $(ls -la "$BUILD_OUTPUT_PATH/Contents/MacOS/desktop_lyric" | awk '{print $5}') bytes"
echo ""
echo "Next steps:"
echo "1. Build the main application: $FLUTTER_CMD build macos $BUILD_TYPE"
echo "2. Install desktop_lyric to app bundle:"
echo "   $SCRIPT_DIR/build_desktop_lyric.sh --build-mode $BUILD_MODE --install-to-app"
echo "3. Run the application and test the desktop lyric feature"