#pragma once

#include <algorithm>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <optional>
#include <string>
#include <utility>
#include <vector>

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

    bool add(std::string title, Priority priority, std::optional<std::time_t> due) {
        auto previous = tasks_;
        int previousNextId = nextId_;
        tasks_.push_back({nextId_++, std::move(title), false, priority, due});
        return saveOrRestore(std::move(previous), previousNextId);
    }

    bool update(int id, std::string title, Priority priority, std::optional<std::time_t> due) {
        Task* task = find(id);
        if (!task) return true;
        auto previous = tasks_;
        task->title = std::move(title);
        task->priority = priority;
        task->due = due;
        return saveOrRestore(std::move(previous), nextId_);
    }

    bool toggle(int id) {
        Task* task = find(id);
        if (!task) return true;
        auto previous = tasks_;
        task->completed = !task->completed;
        return saveOrRestore(std::move(previous), nextId_);
    }

    bool remove(int id) {
        if (!find(id)) return true;
        auto previous = tasks_;
        tasks_.erase(std::remove_if(tasks_.begin(), tasks_.end(),
                                    [id](const Task& task) { return task.id == id; }),
                     tasks_.end());
        return saveOrRestore(std::move(previous), nextId_);
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

    bool saveOrRestore(std::vector<Task> previous, int previousNextId) {
        if (save()) return true;
        tasks_ = std::move(previous);
        nextId_ = previousNextId;
        return false;
    }

    bool save() const {
        auto temporary = path_;
        temporary += ".tmp";
        try {
            std::filesystem::create_directories(path_.parent_path());
            std::ofstream output;
            output.exceptions(std::ios::failbit | std::ios::badbit);
            output.open(temporary, std::ios::trunc);
            for (const Task& task : tasks_) {
                output << task.id << ' ' << task.completed << ' '
                       << static_cast<int>(task.priority) << ' '
                       << (task.due ? *task.due : 0) << ' '
                       << std::quoted(task.title) << '\n';
            }
            output.close();
            std::filesystem::rename(temporary, path_);
            return true;
        } catch (const std::exception&) {
            std::error_code ignored;
            std::filesystem::remove(temporary, ignored);
            return false;
        }
    }
};
