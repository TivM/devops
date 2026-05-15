package com.taskmanager.entity;

import com.fasterxml.jackson.annotation.JsonProperty;

import jakarta.persistence.*;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import java.time.Instant;

@Entity
@Table(name = "tasks")
public class Task {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @NotBlank
    @Column(nullable = false)
    private String title;

    @Column(length = 2000)
    private String description = "";

    @Pattern(regexp = "pending|in_progress|done")
    @Column(nullable = false)
    private String status = "pending";

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    @PreUpdate
    public void preUpdate() {
        this.updatedAt = Instant.now();
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description != null ? description : ""; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status != null ? status : "pending"; }

    @JsonProperty("created_at")
    public String getCreatedAt() { return createdAt != null ? createdAt.toString() : null; }

    @JsonProperty("updated_at")
    public String getUpdatedAt() { return updatedAt != null ? updatedAt.toString() : null; }
}
