import { PinCard } from './PinCard.jsx';
export function PinGrid({ pins, columns, onPinClick }) {
  if (pins.length === 0) {
    return (
      <div style={{ textAlign: 'center', padding: '60px', color: 'var(--text-sec)' }}>
        <i class="fas fa-thumbtack" style={{ fontSize: '48px', marginBottom: '16px' }} />
        <h3>No pins yet</h3>
        <p>Click + to add your first pin!</p>
      </div>
    );
  }
  const containerWidth = Math.min(1400, window.innerWidth - 32);
  const gap = 16;
  const colWidth = (containerWidth - (columns - 1) * gap) / columns;
  const columnHeights = new Array(columns).fill(0);
  const columnPins = new Array(columns).fill(null).map(() => []);
  pins.forEach(pin => {
    let minHeight = Infinity, minIndex = 0;
    for (let i = 0; i < columns; i++) {
      if (columnHeights[i] < minHeight) { minHeight = columnHeights[i]; minIndex = i; }
    }
    const aspectRatio = pin.imageWidth && pin.imageHeight ? pin.imageHeight / pin.imageWidth : 1.2;
    const pinHeight = colWidth * aspectRatio;
    columnPins[minIndex].push({ ...pin, height: pinHeight });
    columnHeights[minIndex] += pinHeight + gap;
  });
  return (
    <div style={{ display: 'grid', gridTemplateColumns: `repeat(${columns}, 1fr)`, gap: '16px', alignItems: 'start' }}>
      {columnPins.map((column, colIndex) => (
        <div key={colIndex} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
          {column.map(pin => <PinCard key={pin.id} pin={pin} onClick={() => onPinClick(pin)} />)}
        </div>
      ))}
    </div>
  );
}
