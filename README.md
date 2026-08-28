# Todo List

A dependency-free macOS desktop to-do list written in C++17 and Objective-C++ (for the native AppKit UI).

## Build and run

```sh
cmake -S . -B build
cmake --build build
open build/TodoList.app
```

Tasks are saved automatically in `~/Library/Application Support/TodoList/tasks.txt`.

Run the model and persistence check with:

```sh
./build/TodoList.app/Contents/MacOS/TodoList --self-test
```
