#import <AppKit/AppKit.h>

#include <cassert>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <optional>
#include <sstream>
#include <string>
#include <vector>
#include <unistd.h>

enum class Priority { None, Low, Medium, High };
enum class Filter { All, Active, Completed };

struct Task {
    int id{};
    std::string title;
    bool completed{};
    Priority priority{Priority::None};
    std::optional<std::time_t> due;
};

class TaskStore {
public:
    TaskStore() = default;
    explicit TaskStore(std::filesystem::path path) : path_(std::move(path)) { load(); }

    const std::vector<Task>& tasks() const { return tasks_; }

    void add(std::string title, Priority priority, std::optional<std::time_t> due) {
        tasks_.push_back({nextId_++, std::move(title), false, priority, due});
        save();
    }

    void update(int id, std::string title, Priority priority, std::optional<std::time_t> due) {
        if (Task* task = find(id)) {
            task->title = std::move(title);
            task->priority = priority;
            task->due = due;
            save();
        }
    }

    void toggle(int id) {
        if (Task* task = find(id)) {
            task->completed = !task->completed;
            save();
        }
    }

    void remove(int id) {
        tasks_.erase(std::remove_if(tasks_.begin(), tasks_.end(),
                                    [id](const Task& task) { return task.id == id; }),
                     tasks_.end());
        save();
    }

    std::vector<size_t> visible(Filter filter) const {
        std::vector<size_t> result;
        for (size_t i = 0; i < tasks_.size(); ++i) {
            if (filter == Filter::All ||
                (filter == Filter::Active && !tasks_[i].completed) ||
                (filter == Filter::Completed && tasks_[i].completed)) {
                result.push_back(i);
            }
        }
        return result;
    }

private:
    std::filesystem::path path_;
    std::vector<Task> tasks_;
    int nextId_{1};

    Task* find(int id) {
        auto it = std::find_if(tasks_.begin(), tasks_.end(),
                               [id](const Task& task) { return task.id == id; });
        return it == tasks_.end() ? nullptr : &*it;
    }

    void load() {
        std::ifstream input(path_);
        Task task;
        long long due{};
        int completed{}, priority{};
        while (input >> task.id >> completed >> priority >> due >> std::quoted(task.title)) {
            task.completed = completed != 0;
            task.priority = static_cast<Priority>(std::clamp(priority, 0, 3));
            task.due = due == 0 ? std::nullopt : std::optional<std::time_t>(due);
            tasks_.push_back(task);
            nextId_ = std::max(nextId_, task.id + 1);
        }
    }

    void save() const {
        std::filesystem::create_directories(path_.parent_path());
        std::ofstream output(path_, std::ios::trunc);
        for (const Task& task : tasks_) {
            output << task.id << ' ' << task.completed << ' '
                   << static_cast<int>(task.priority) << ' '
                   << (task.due ? *task.due : 0) << ' '
                   << std::quoted(task.title) << '\n';
        }
    }
};

static std::filesystem::path taskFilePath() {
    NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString* base = paths.firstObject ?: NSTemporaryDirectory();
    return std::filesystem::path(base.UTF8String) / "TodoList" / "tasks.txt";
}

static NSString* priorityName(Priority priority) {
    switch (priority) {
        case Priority::Low: return @"Low";
        case Priority::Medium: return @"Medium";
        case Priority::High: return @"High";
        default: return @"None";
    }
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation AppDelegate {
    NSWindow* _window;
    NSTableView* _table;
    NSSegmentedControl* _filter;
    NSTextField* _titleField;
    NSButton* _hasDueDate;
    NSDatePicker* _dueDate;
    NSPopUpButton* _priority;
    TaskStore _store;
    std::vector<size_t> _visible;
}

- (instancetype)init {
    if ((self = [super init])) {
        _store = TaskStore(taskFilePath());
        _visible = _store.visible(Filter::All);
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    [self buildMenu];
    [self buildWindow];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

- (void)buildMenu {
    NSMenu* menuBar = [[NSMenu alloc] init];
    NSMenuItem* appItem = [[NSMenuItem alloc] init];
    [menuBar addItem:appItem];
    NSMenu* appMenu = [[NSMenu alloc] initWithTitle:@"Todo List"];
    [appMenu addItemWithTitle:@"Quit Todo List" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    NSApp.mainMenu = menuBar;
}

- (void)buildWindow {
    _window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 760, 520)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    _window.title = @"Todo List";
    [_window center];
    _window.minSize = NSMakeSize(640, 420);

    NSView* content = _window.contentView;

    _filter = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(20, 475, 300, 28)];
    _filter.segmentCount = 3;
    [_filter setLabel:@"All" forSegment:0];
    [_filter setLabel:@"Active" forSegment:1];
    [_filter setLabel:@"Completed" forSegment:2];
    _filter.selectedSegment = 0;
    _filter.target = self;
    _filter.action = @selector(filterChanged:);
    _filter.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
    [content addSubview:_filter];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 145, 720, 315)];
    scroll.hasVerticalScroller = YES;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.allowsMultipleSelection = NO;
    _table.delegate = self;
    _table.dataSource = self;

    NSArray<NSArray*>* columns = @[
        @[@"done", @"Done", @70], @[@"task", @"Task", @360],
        @[@"due", @"Due date", @140], @[@"priority", @"Priority", @110]
    ];
    for (NSArray* spec in columns) {
        NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:spec[0]];
        column.title = spec[1];
        column.width = [spec[2] doubleValue];
        if ([spec[0] isEqual:@"task"]) column.resizingMask = NSTableColumnAutoresizingMask;
        [_table addTableColumn:column];
    }
    scroll.documentView = _table;
    [content addSubview:scroll];

    _titleField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 340, 28)];
    _titleField.placeholderString = @"What needs doing?";
    _titleField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_titleField];

    _priority = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(370, 100, 110, 28)];
    [_priority addItemsWithTitles:@[@"None", @"Low", @"Medium", @"High"]];
    _priority.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:_priority];

    _hasDueDate = [NSButton checkboxWithTitle:@"Due" target:self action:@selector(dueToggled:)];
    _hasDueDate.frame = NSMakeRect(490, 100, 55, 28);
    _hasDueDate.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:_hasDueDate];

    _dueDate = [[NSDatePicker alloc] initWithFrame:NSMakeRect(545, 100, 195, 28)];
    _dueDate.datePickerElements = NSDatePickerElementFlagYearMonthDay;
    _dueDate.enabled = NO;
    _dueDate.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [content addSubview:_dueDate];

    NSArray<NSArray*>* buttons = @[
        @[@"Add", @"addTask:", @20], @[@"Update Selected", @"updateTask:", @110],
        @[@"Toggle Complete", @"toggleTask:", @265], @[@"Delete", @"deleteTask:", @415]
    ];
    for (NSArray* spec in buttons) {
        NSButton* button = [NSButton buttonWithTitle:spec[0]
                                             target:self
                                             action:NSSelectorFromString(spec[1])];
        button.frame = NSMakeRect([spec[2] doubleValue], 50,
                                  [spec[0] isEqual:@"Update Selected"] ? 145 :
                                  [spec[0] isEqual:@"Toggle Complete"] ? 140 : 80, 32);
        button.autoresizingMask = NSViewMaxYMargin;
        [content addSubview:button];
    }
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_visible.size());
}

- (NSView*)tableView:(NSTableView*)tableView
   viewForTableColumn:(NSTableColumn*)column
                  row:(NSInteger)row {
    (void)tableView;
    const Task& task = _store.tasks()[_visible[static_cast<size_t>(row)]];
    NSTextField* cell = [NSTextField labelWithString:@""];
    if ([column.identifier isEqual:@"done"]) {
        cell.stringValue = task.completed ? @"✓" : @"";
        cell.alignment = NSTextAlignmentCenter;
    } else if ([column.identifier isEqual:@"task"]) {
        cell.stringValue = [NSString stringWithUTF8String:task.title.c_str()];
        if (task.completed) {
            cell.attributedStringValue = [[NSAttributedString alloc]
                initWithString:cell.stringValue
                    attributes:@{NSStrikethroughStyleAttributeName: @1,
                                 NSForegroundColorAttributeName: NSColor.secondaryLabelColor}];
        }
    } else if ([column.identifier isEqual:@"due"]) {
        if (task.due) {
            NSDate* date = [NSDate dateWithTimeIntervalSince1970:*task.due];
            cell.stringValue = [NSDateFormatter localizedStringFromDate:date
                                                              dateStyle:NSDateFormatterMediumStyle
                                                              timeStyle:NSDateFormatterNoStyle];
        }
    } else {
        cell.stringValue = priorityName(task.priority);
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification;
    const Task* task = [self selectedTask];
    if (!task) return;
    _titleField.stringValue = [NSString stringWithUTF8String:task->title.c_str()];
    [_priority selectItemAtIndex:static_cast<NSInteger>(task->priority)];
    _hasDueDate.state = task->due ? NSControlStateValueOn : NSControlStateValueOff;
    _dueDate.enabled = task->due.has_value();
    if (task->due) _dueDate.dateValue = [NSDate dateWithTimeIntervalSince1970:*task->due];
}

- (const Task*)selectedTask {
    NSInteger row = _table.selectedRow;
    if (row < 0 || static_cast<size_t>(row) >= _visible.size()) return nullptr;
    return &_store.tasks()[_visible[static_cast<size_t>(row)]];
}

- (std::optional<std::time_t>)dueValue {
    if (_hasDueDate.state != NSControlStateValueOn) return std::nullopt;
    return static_cast<std::time_t>(_dueDate.dateValue.timeIntervalSince1970);
}

- (BOOL)editorIsValid {
    NSString* title = [_titleField.stringValue
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (title.length > 0) return YES;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Enter a task name.";
    [alert beginSheetModalForWindow:_window completionHandler:nil];
    return NO;
}

- (void)addTask:(id)sender {
    (void)sender;
    if (![self editorIsValid]) return;
    _store.add(_titleField.stringValue.UTF8String,
               static_cast<Priority>(_priority.indexOfSelectedItem), [self dueValue]);
    [self clearEditor];
    [self reload];
}

- (void)updateTask:(id)sender {
    (void)sender;
    const Task* task = [self selectedTask];
    if (!task || ![self editorIsValid]) return;
    int id = task->id;
    _store.update(id, _titleField.stringValue.UTF8String,
                  static_cast<Priority>(_priority.indexOfSelectedItem), [self dueValue]);
    [self reload];
}

- (void)toggleTask:(id)sender {
    (void)sender;
    const Task* task = [self selectedTask];
    if (!task) return;
    _store.toggle(task->id);
    [self reload];
}

- (void)deleteTask:(id)sender {
    (void)sender;
    const Task* task = [self selectedTask];
    if (!task) return;
    _store.remove(task->id);
    [self clearEditor];
    [self reload];
}

- (void)filterChanged:(id)sender { (void)sender; [self reload]; }
- (void)dueToggled:(id)sender { (void)sender; _dueDate.enabled = _hasDueDate.state == NSControlStateValueOn; }

- (void)clearEditor {
    _titleField.stringValue = @"";
    [_priority selectItemAtIndex:0];
    _hasDueDate.state = NSControlStateValueOff;
    _dueDate.enabled = NO;
}

- (void)reload {
    _visible = _store.visible(static_cast<Filter>(_filter.selectedSegment));
    [_table reloadData];
}

@end

static void selfTest() {
    auto path = std::filesystem::temp_directory_path() /
                ("todo-list-test-" + std::to_string(getpid()) + ".txt");
    {
        TaskStore store(path);
        store.add("Write tests", Priority::High, std::time(nullptr) + 86400);
        store.add("Ship app", Priority::Medium, std::nullopt);
        assert(store.tasks().size() == 2);
        store.toggle(store.tasks()[0].id);
        assert(store.visible(Filter::Completed).size() == 1);
        store.update(store.tasks()[1].id, "Ship desktop app", Priority::High, std::nullopt);
    }
    {
        TaskStore loaded(path);
        assert(loaded.tasks().size() == 2);
        assert(loaded.tasks()[0].completed);
        assert(loaded.tasks()[1].title == "Ship desktop app");
        loaded.remove(loaded.tasks()[0].id);
        assert(loaded.tasks().size() == 1);
    }
    std::filesystem::remove(path);
}

int main(int argc, const char* argv[]) {
    if (argc == 2 && std::string(argv[1]) == "--self-test") {
        selfTest();
        return 0;
    }
    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;
        AppDelegate* delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
