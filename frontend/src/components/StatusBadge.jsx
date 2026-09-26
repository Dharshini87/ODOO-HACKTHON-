const STYLES = {
  draft: "bg-status-draft/15 text-status-draft border-status-draft/30",
  waiting: "bg-status-waiting/15 text-status-waiting border-status-waiting/30",
  ready: "bg-status-ready/15 text-status-ready border-status-ready/30",
  done: "bg-status-done/15 text-status-done border-status-done/30",
  cancelled: "bg-status-cancelled/15 text-status-cancelled border-status-cancelled/30",
};

const LABELS = {
  draft: "Draft",
  waiting: "Waiting",
  ready: "Ready",
  done: "Done",
  cancelled: "Cancelled",
};

export default function StatusBadge({ status }) {
  const cls = STYLES[status] || STYLES.draft;
  return (
    <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-medium border ${cls}`}>
      {LABELS[status] || status}
    </span>
  );
}
