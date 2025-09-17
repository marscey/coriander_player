# ==============================================================================
# CMakeLists.txt 文件作用：
# 这是 Flutter 项目在 Windows 平台的主构建配置文件，负责定义项目结构、编译设置、
# 依赖管理和安装规则。该文件使用 CMake 构建系统来协调 Flutter 应用的 Windows 平台构建过程。
# ==============================================================================

# 项目级配置：指定最低 CMake 版本要求和项目基本信息
# 设置 CMake 最低版本要求为 3.14，项目名称为 coriander_player，使用 C++ 语言
cmake_minimum_required(VERSION 3.14)
project(coriander_player LANGUAGES CXX)

# 设置应用程序可执行文件的名称
# 修改此值可以更改最终生成的可执行文件名
set(BINARY_NAME "coriander_player")

# 显式选择现代 CMake 行为，以避免在新版本 CMake 中出现警告
cmake_policy(VERSION 3.14...3.25)

# 定义构建配置选项
# 检查是否使用多配置生成器（如 Visual Studio）
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  # 对于多配置生成器，设置可用的配置类型为 Debug、Profile 和 Release
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  # 对于单配置生成器，如果未设置构建类型，则默认设置为 Debug
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

# 定义 Profile 构建模式的设置
# Profile 模式通常使用 Release 的优化设置但保留调试信息
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# 为所有项目启用 Unicode 支持
add_definitions(-DUNICODE -D_UNICODE)

# 定义应用于大多数目标的编译设置
# 注意：谨慎添加新选项，因为插件默认使用此函数
function(APPLY_STANDARD_SETTINGS TARGET)
  # 指定目标需要 C++17 标准
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  # 设置编译选项：警告级别 4，将警告视为错误，禁用未使用参数的警告
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  # 设置异常处理模式
  target_compile_options(${TARGET} PRIVATE /EHsc)
  # 禁用 C++ 异常处理以提高性能
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  # 在 Debug 配置下定义 _DEBUG 宏
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# 设置 Flutter 库和工具的构建规则
# 指定 Flutter 管理目录的路径
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
# 添加 Flutter 管理目录作为子目录进行构建
add_subdirectory(${FLUTTER_MANAGED_DIR})

# 应用程序构建配置
# 引用 runner 目录中的 CMakeLists.txt 文件，该文件包含实际应用程序的构建规则
add_subdirectory("runner")

# 生成的插件构建规则
# 包含自动生成的插件构建配置，管理插件的构建并将它们添加到应用程序中
include(flutter/generated_plugins.cmake)

# ==============================================================================
# 安装配置部分
# 此部分定义了构建后如何安装和部署应用程序所需的文件
# ==============================================================================

# 支持文件被复制到可执行文件旁边，以便应用程序可以在原地运行
# 这样做是为了使在 Visual Studio 中构建和运行更加方便，而不是像 Linux 那样创建单独的包
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# 使 "install" 步骤成为默认步骤，因为它是运行所必需的
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)

# 如果未初始化 CMAKE_INSTALL_PREFIX，则将其设置为构建捆绑目录
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# 定义安装目录结构
set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")  # 数据文件目录
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")        # 库文件目录

# 安装可执行文件到安装前缀目录
install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# 安装 Flutter ICU 数据文件
install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

# 安装 Flutter 库文件
install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

# 如果有插件捆绑的库文件，也安装它们
if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# 复制所有包的 build.dart 提供的原生资产
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# 在每次构建时完全重新复制资源目录，以避免来自先前安装的过时文件
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# 仅在非 Debug 构建（Profile 和 Release）中安装 AOT 库
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# ==============================================================================
# BASS 库配置部分
# 此部分定义了如何将 BASS 音频库文件复制到构建输出目录
# ==============================================================================

# 定义 BASS 库的源目录
set(BASS_LIB_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/bass")

# 定义 BASS 库的目标目录（在安装目录中创建 BASS 子目录）
set(BASS_LIB_TARGET_DIR "${INSTALL_BUNDLE_LIB_DIR}/BASS")

# 将所有 BASS 库文件复制到目标目录
install(DIRECTORY "${BASS_LIB_SOURCE_DIR}/"
  DESTINATION "${BASS_LIB_TARGET_DIR}"
  COMPONENT Runtime
  FILES_MATCHING PATTERN "*.dll")
  