const API_URL = import.meta.env.VITE_API_URL || '/api';

function buildTaskUrl(id) {
  const taskId = Number(id);
  if (!Number.isInteger(taskId) || taskId <= 0 || String(taskId) !== String(id)) {
    throw new Error('Invalid task id');
  }
  return `${API_URL}/tasks/${encodeURIComponent(String(taskId))}`;
}

async function parseJsonResponse(res, fallbackMessage) {
  const contentType = res.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    return res.json();
  }
  if (!res.ok) {
    throw new Error(fallbackMessage);
  }
  throw new Error('Expected JSON response');
}

async function throwApiError(res, fallbackMessage) {
  const contentType = res.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    const err = await res.json();
    throw new Error(err.error || fallbackMessage);
  }
  throw new Error(fallbackMessage);
}

export async function fetchTasks() {
  const res = await fetch(`${API_URL}/tasks`);
  if (!res.ok) throw new Error('Failed to fetch tasks');
  return parseJsonResponse(res, 'Failed to fetch tasks');
}

export async function createTask(data) {
  const res = await fetch(`${API_URL}/tasks`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    await throwApiError(res, 'Failed to create task');
  }
  return parseJsonResponse(res, 'Failed to create task');
}

export async function updateTask(id, data) {
  const res = await fetch(buildTaskUrl(id), {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    await throwApiError(res, 'Failed to update task');
  }
  return parseJsonResponse(res, 'Failed to update task');
}

export async function deleteTask(id) {
  const res = await fetch(buildTaskUrl(id), {
    method: 'DELETE',
  });
  if (!res.ok) throw new Error('Failed to delete task');
  return parseJsonResponse(res, 'Failed to delete task');
}
