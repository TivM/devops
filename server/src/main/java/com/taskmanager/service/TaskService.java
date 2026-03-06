package com.taskmanager.service;

import com.taskmanager.entity.Task;
import com.taskmanager.repository.TaskRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

@Service
public class TaskService {

    private static final List<String> VALID_STATUSES = List.of("pending", "in_progress", "done");

    private final TaskRepository repository;

    public TaskService(TaskRepository repository) {
        this.repository = repository;
    }

    public List<Task> findAll() {
        return repository.findAllByOrderByCreatedAtDesc();
    }

    public Optional<Task> findById(Long id) {
        return repository.findById(id);
    }

    @Transactional
    public Task create(String title, String description, String status) {
        Task task = new Task();
        task.setTitle(title != null ? title.trim() : "");
        task.setDescription(description != null ? description : "");
        task.setStatus(status != null && VALID_STATUSES.contains(status) ? status : "pending");
        return repository.save(task);
    }

    @Transactional
    public Optional<Task> update(Long id, String title, String description, String status) {
        return repository.findById(id).map(task -> {
            if (title != null) task.setTitle(title.trim());
            if (description != null) task.setDescription(description);
            if (status != null && VALID_STATUSES.contains(status)) task.setStatus(status);
            return repository.save(task);
        });
    }

    @Transactional
    public Optional<Task> deleteById(Long id) {
        Optional<Task> task = repository.findById(id);
        task.ifPresent(repository::delete);
        return task;
    }
}
