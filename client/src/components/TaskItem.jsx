import PropTypes from 'prop-types';

const STATUS_LABELS = {
  pending: 'Pending',
  in_progress: 'In Progress',
  done: 'Done',
};

const NEXT_STATUS = {
  pending: 'in_progress',
  in_progress: 'done',
  done: 'pending',
};

export default function TaskItem({ task, onUpdate, onDelete }) {
  const handleStatusChange = () => {
    onUpdate(task.id, { status: NEXT_STATUS[task.status] });
  };

  return (
    <div className={`task-item task-${task.status}`}>
      <div className="task-content">
        <h3>{task.title}</h3>
        {task.description && <p>{task.description}</p>}
      </div>
      <div className="task-actions">
        <button
          className={`status-btn status-${task.status}`}
          onClick={handleStatusChange}
          aria-label="Change status"
        >
          {STATUS_LABELS[task.status]}
        </button>
        <button
          className="delete-btn"
          onClick={() => onDelete(task.id)}
          aria-label="Delete task"
        >
          Delete
        </button>
      </div>
    </div>
  );
}

TaskItem.propTypes = {
  task: PropTypes.shape({
    id: PropTypes.number.isRequired,
    title: PropTypes.string.isRequired,
    description: PropTypes.string,
    status: PropTypes.oneOf(Object.keys(STATUS_LABELS)).isRequired,
  }).isRequired,
  onUpdate: PropTypes.func.isRequired,
  onDelete: PropTypes.func.isRequired,
};
