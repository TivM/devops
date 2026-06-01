package com.taskmanager.controller;

import com.taskmanager.entity.Task;
import com.taskmanager.service.TaskService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/tasks")
public class TaskController {

    private static final String TITLE_REQUIRED_MESSAGE = "Title is required";
    private static final String TITLE_EMPTY_MESSAGE = "Title cannot be empty";
    private static final String INVALID_STATUS_MESSAGE = "Invalid status";
    private static final String TASK_DELETED_MESSAGE = "Task deleted";
    private static final List<String> VALID_STATUSES = List.of("pending", "in_progress", "done");

    private final TaskService taskService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    @GetMapping
    public List<Task> getAll() {
        return taskService.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<Task> getById(@PathVariable Long id) {
        return taskService.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public ResponseEntity<Object> create(@RequestBody TaskRequest body) {
        if (body == null) {
            return ResponseEntity.badRequest().body(new ErrorResponse(TITLE_REQUIRED_MESSAGE));
        }
        String title = body.title();
        if (title == null || title.trim().isEmpty()) {
            return ResponseEntity.badRequest().body(new ErrorResponse(TITLE_REQUIRED_MESSAGE));
        }
        String status = body.status();
        if (status != null && !VALID_STATUSES.contains(status)) {
            return ResponseEntity.badRequest().body(new ErrorResponse(INVALID_STATUS_MESSAGE));
        }
        Task task = taskService.create(title, body.description(), status);
        return ResponseEntity.status(HttpStatus.CREATED).body(task);
    }

    @PutMapping("/{id}")
    public ResponseEntity<Object> update(@PathVariable Long id, @RequestBody TaskRequest body) {
        if (body != null && body.title() != null && body.title().trim().isEmpty()) {
            return ResponseEntity.badRequest().body(new ErrorResponse(TITLE_EMPTY_MESSAGE));
        }
        String status = body != null ? body.status() : null;
        if (status != null && !VALID_STATUSES.contains(status)) {
            return ResponseEntity.badRequest().body(new ErrorResponse(INVALID_STATUS_MESSAGE));
        }
        String title = body != null ? body.title() : null;
        String description = body != null ? body.description() : null;
        return taskService.update(id, title, description, status)
                .<ResponseEntity<Object>>map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Object> delete(@PathVariable Long id) {
        return taskService.deleteById(id)
                .<ResponseEntity<Object>>map(task -> ResponseEntity.ok(new DeleteResponse(TASK_DELETED_MESSAGE, task)))
                .orElse(ResponseEntity.notFound().build());
    }

    public record TaskRequest(String title, String description, String status) {
    }

    public record ErrorResponse(String error) {
    }

    public record DeleteResponse(String message, Task task) {
    }
}
