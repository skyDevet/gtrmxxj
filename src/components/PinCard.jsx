export function PinCard({ pin, onClick }) {
  return (
    <div
      style={{
        borderRadius: '12px', overflow: 'hidden', background: 'var(--border)',
        cursor: 'pointer', transition: 'transform 0.2s ease, box-shadow 0.2s ease',
        boxShadow: '0 1px 3px rgba(0,0,0,0.1)', height: `${pin.height}px`, position: 'relative'
      }}
      onClick={onClick}
      onMouseEnter={(e) => { e.currentTarget.style.transform = 'scale(1.02)'; e.currentTarget.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)'; }}
      onMouseLeave={(e) => { e.currentTarget.style.transform = 'scale(1)'; e.currentTarget.style.boxShadow = '0 1px 3px rgba(0,0,0,0.1)'; }}
    >
     <img
  src={pin.driveFileId
    ? `https://lh3.googleusercontent.com/d/${pin.driveFileId}`
    : (pin.thumbnail || pin.image)}
  alt={pin.title}
  style={{
    width: '100%',
    height: '100%',
    objectFit: 'cover',
    objectPosition: 'center',
    display: 'block'
  }}
  loading="lazy"
/>
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, padding: '12px', background: 'linear-gradient(to top, rgba(0,0,0,0.7), transparent)', color: 'white' }}>
        <div style={{ fontWeight: '500', fontSize: '14px', marginBottom: '4px' }}>{pin.title}</div>
        <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '11px', opacity: 0.8 }}>
          <span>{pin.category}</span>
          <span><i class="fas fa-heart" style={{ marginRight: '4px' }} />{pin.likes || 0}</span>
        </div>
        {pin.class && <div style={{ fontSize: '10px', opacity: 0.6, marginTop: '4px' }}>#{pin.class}</div>}
      </div>
    </div>
  );
}
