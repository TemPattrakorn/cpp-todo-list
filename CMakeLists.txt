cmake_minimum_required(VERSION 3.20)
project(TodoList LANGUAGES CXX OBJCXX)

add_executable(TodoList MACOSX_BUNDLE src/main.mm src/app_ui.mm src/self_test.mm)
target_compile_features(TodoList PRIVATE cxx_std_17)
target_compile_options(TodoList PRIVATE -fobjc-arc)
target_link_libraries(TodoList PRIVATE "-framework AppKit")

set_target_properties(TodoList PROPERTIES
    MACOSX_BUNDLE_BUNDLE_NAME "Todo List"
    MACOSX_BUNDLE_GUI_IDENTIFIER "local.todo-list"
)
