#include "task_store.h"

#include <cassert>
#include <unistd.h>

void selfTest() {
    auto path = std::filesystem::temp_directory_path() /
                ("todo-list-test-" + std::to_string(getpid()) + ".txt");
    auto temporary = path;
    temporary += ".tmp";
    auto due = std::time(nullptr) + 86400;
    {
        TaskStore store(path);
        assert(store.add("Write \"tests\"", Priority::High, due));
        assert(store.add("Ship app", Priority::Medium, std::nullopt));
        assert(store.tasks().size() == 2);
        assert(store.toggle(store.tasks()[0].id));
        assert(store.visible(Filter::Completed).size() == 1);
        assert(store.update(store.tasks()[1].id, "Ship desktop app", Priority::High,
                            std::nullopt));
        assert(!std::filesystem::exists(temporary));
    }
    {
        TaskStore loaded(path);
        assert(loaded.tasks().size() == 2);
        assert(loaded.tasks()[0].id == 1);
        assert(loaded.tasks()[0].title == "Write \"tests\"");
        assert(loaded.tasks()[0].completed);
        assert(loaded.tasks()[0].priority == Priority::High);
        assert(loaded.tasks()[0].due == due);
        assert(loaded.tasks()[1].id == 2);
        assert(loaded.tasks()[1].title == "Ship desktop app");
        assert(loaded.tasks()[1].priority == Priority::High);
        assert(!loaded.tasks()[1].due);
        assert(loaded.remove(loaded.tasks()[0].id));
        assert(loaded.tasks().size() == 1);
        std::filesystem::create_directory(temporary);
        assert(!loaded.add("Must roll back", Priority::None, std::nullopt));
        assert(loaded.tasks().size() == 1);
        assert(!std::filesystem::exists(temporary));
        TaskStore unchanged(path);
        assert(unchanged.tasks().size() == 1);
        assert(unchanged.tasks()[0].title == "Ship desktop app");
        assert(loaded.add("After failure", Priority::Low, std::nullopt));
        assert(loaded.tasks().back().id == 3);
        TaskStore recovered(path);
        assert(recovered.tasks().size() == 2);
        assert(recovered.tasks().back().id == 3);
    }
    std::filesystem::remove(path);
}
