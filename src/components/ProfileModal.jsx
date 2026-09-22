import { signOut } from '../services/auth.js';

export function ProfileModal({ pins, classes, aiReady, darkMode, user, onClose, onClearAll, onToggleTheme }) {
  const counts = {};
  const classCounts = {};
  pins.forEach(p => {
    const cat = p.category || 'Uncategorized';
    counts[cat] = (counts[cat] || 0) + 1;
    if (p.class) classCounts[p.class] = (classCounts[p.class] || 0) + 1;
  });
  const aiCount = pins.filter(p => p.features).length;

  return (
    <div
      style={{
        position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
        background: 'rgba(0,0,0,0.7)', zIndex: 999,
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px'
      }}
      onClick={onClose}
    >
      <div
        style={{
          background: 'var(--card)', borderRadius: '16px', maxWidth: '500px',
          width: '100%', maxHeight: '90vh', overflow: 'auto', padding: '24px'
        }}
        onClick={(e) => e.stopPropagation()}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
          <h3 style={{ color: 'var(--text)', margin: 0 }}>Profile</h3>
          <button style={{ background: 'none', border: 'none', color: 'var(--text-sec)', cursor: 'pointer', fontSize: '20px' }} onClick={onClose}>
            <i class="fas fa-times" />
          </button>
        </div>

        {user && (
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px', marginBottom: '20px', padding: '12px', background: 'var(--bg)', borderRadius: '12px' }}>
            <img src={user.picture} alt={user.name} style={{ width: '48px', height: '48px', borderRadius: '50%' }} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontWeight: 600, color: 'var(--text)' }}>{user.name}</div>
              <div style={{ fontSize: '12px', color: 'var(--text-sec)', overflow: 'hidden', textOverflow: 'ellipsis' }}>{user.email}</div>
              <div style={{ fontSize: '11px', color: '#22c55e', marginTop: '2px' }}>
                <i class="fas fa-check-circle" /> Google Drive connected
              </div>
            </div>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: '12px', marginBottom: '24px' }}>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--text)' }}>{pins.length}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>Total</div>
          </div>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: 'var(--text)' }}>{Object.keys(counts).length}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>Categories</div>
          </div>
          <div style={{ textAlign: 'center', padding: '16px', background: 'var(--bg)', borderRadius: '12px' }}>
            <div style={{ fontSize: '28px', fontWeight: 'bold', color: '#667eea' }}>{aiCount}</div>
            <div style={{ fontSize: '12px', color: 'var(--text-sec)' }}>AI Pins</div>
          </div>
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          <button
            style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text)', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
            onClick={onToggleTheme}
          >
            <i class={`fas ${darkMode ? 'fa-sun' : 'fa-moon'}`} />
            {darkMode ? 'Light Mode' : 'Dark Mode'}
          </button>

          <button
            style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid #ef4444', background: 'transparent', color: '#ef4444', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
            onClick={onClearAll}
          >
            <i class="fas fa-trash" /> Clear All (disabled)
          </button>

          {user && (
            <button
              style={{ padding: '10px 16px', borderRadius: '8px', border: '1px solid var(--border)', background: 'transparent', color: 'var(--text)', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: '8px' }}
              onClick={signOut}
            >
              <i class="fas fa-sign-out-alt" /> Sign out
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
