/**
 * One figure with its label under it.
 *
 * The figure sits ABOVE the label, which is the reference's order and the readable one: the number
 * is what the tile is for, and a label above it makes the eye read a caption before the answer.
 */
export function StatTile({
  value,
  label,
  className = '',
}: {
  value: string;
  label: string;
  className?: string;
}) {
  return (
    <div className={`card flex flex-col justify-between px-5 py-[18px] ${className}`}>
      <p className="text-figure font-medium text-ink">{value}</p>
      <p className="mt-6 text-[12px] text-ink-muted">{label}</p>
    </div>
  );
}
