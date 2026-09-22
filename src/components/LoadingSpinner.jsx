export function LoadingSpinner({ aiStatus, aiProgress }) {
  return (
    <div style={{ minHeight: '100vh', flexDirection: 'column', gap: '16px', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <i class="fas fa-spinner fa-pulse" style={{ fontSize: '32px', color: 'var(--primary)' }} />
      <p style={{ color: 'var(--text-sec)' }}>Loading...</p>
      <div style={{ width: '300px' }}>
        <p style={{ fontSize: '12px', color: 'var(--text-sec)', marginBottom: '8px' }}>{aiStatus}</p>
        <div class="progress-bar"><div class="progress-fill" style={{ width: `${aiProgress}%` }} /></div>
      </div>
    </div>
  );
}
