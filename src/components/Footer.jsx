export function Footer({ activeTab, onHome, onUpload, onProfile }) {
  const iconStyle = (tab) => ({
    background: 'none', border: 'none', cursor: 'pointer', fontSize: '22px',
    color: activeTab === tab ? 'var(--primary)' : 'var(--text-sec)',
    padding: '8px 28px', display: 'flex', alignItems: 'center', justifyContent: 'center'
  });
  return (
    <nav style={{
      position: 'fixed', bottom: 0, left: 0, right: 0, background: 'var(--card)',
      borderTop: '1px solid var(--border)', borderTopLeftRadius: '32px', borderTopRightRadius: '32px',
      display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '8px',
      zIndex: 100, paddingBottom: 'env(safe-area-inset-bottom, 0)', paddingTop: '6px'
    }}>
      <button style={iconStyle('home')} onClick={onHome} aria-label="Home"><i class="fas fa-home" /></button>
      <button
        onClick={onUpload} aria-label="Add pin"
        style={{
          background: 'var(--primary)', color: 'white', border: '4px solid var(--card)',
          borderRadius: '50%', width: '64px', height: '64px', fontSize: '26px',
          display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
          marginTop: '-34px', boxShadow: '0 4px 12px rgba(0,0,0,0.25)', flexShrink: 0
        }}
      ><i class="fas fa-plus" /></button>
      <button style={iconStyle('profile')} onClick={onProfile} aria-label="Profile"><i class="fas fa-user" /></button>
    </nav>
  );
}
