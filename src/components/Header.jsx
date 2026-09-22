import { LoginButton } from './LoginButton.jsx';

export function Header({
  darkMode, aiReady, searchTerm, filterCategory, selectedClass,
  classes, allCategories, onSearchChange, onFilterChange,
  onClassChange, onToggleTheme, onReset, user, onProfile
}) {
  return (
    <header style={{
      position: 'sticky', top: 0, background: 'var(--card)',
      borderBottom: '1px solid var(--border)', padding: '12px 16px', zIndex: 100
    }}>
      <div style={{
        maxWidth: '1400px', margin: '0 auto', display: 'flex',
        alignItems: 'center', gap: '16px', flexWrap: 'wrap'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', cursor: 'pointer' }} onClick={onReset}>
          <img
            src="/Img/InShot_20260907_212634930.png"
            alt="Logo"
            style={{ width: '24px', height: '24px', objectFit: 'contain' }}
          />
          <span style={{ fontWeight: 'bold', fontSize: '18px', marginLeft: '6px' }}>ገትር</span>
          {aiReady && <span class="ai-badge" style={{ marginLeft: '8px' }}>🤖 AI</span>}
        </div>

        <div style={{
          flex: 1, display: 'flex', alignItems: 'center',
          background: 'var(--border)', borderRadius: '24px',
          padding: '0 14px', minWidth: '200px'
        }}>
          <i class="fas fa-search" style={{ color: 'var(--text-sec)', fontSize: '14px' }} />
          <input
            type="text"
            placeholder="Search pins..."
            value={searchTerm}
            onInput={(e) => onSearchChange(e.target.value)}
            style={{
              flex: 1, padding: '8px 10px', border: 'none',
              background: 'transparent', outline: 'none', fontSize: '14px',
              color: 'var(--text)', width: 'auto'
            }}
          />
        </div>

        <LoginButton user={user} onProfile={onProfile} />
      </div>

      <div style={{ maxWidth: '1400px', margin: '0 auto', paddingTop: '12px' }}>
        <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '8px' }}>
          {allCategories.map(cat => (
            <button
              key={cat}
              class="btn"
              onClick={() => onFilterChange(cat)}
              style={{
                padding: '6px 14px', fontSize: '13px',
                background: filterCategory === cat ? 'var(--primary)' : 'transparent',
                color: filterCategory === cat ? 'white' : 'var(--text-sec)',
                border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
              }}
            >
              {cat.charAt(0).toUpperCase() + cat.slice(1)}
            </button>
          ))}
        </div>
        {classes.length > 0 && (
          <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginTop: '4px' }}>
            <button
              class="btn"
              onClick={() => onClassChange('')}
              style={{
                padding: '4px 12px', fontSize: '12px',
                background: !selectedClass ? 'var(--primary)' : 'transparent',
                color: !selectedClass ? 'white' : 'var(--text-sec)',
                border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
              }}
            >
              All Classes
            </button>
            {classes.map(cls => (
              <button
                key={cls}
                class="btn"
                onClick={() => onClassChange(cls)}
                style={{
                  padding: '4px 12px', fontSize: '12px',
                  background: selectedClass === cls ? 'var(--primary)' : 'transparent',
                  color: selectedClass === cls ? 'white' : 'var(--text-sec)',
                  border: '1px solid var(--border)', borderRadius: '20px', cursor: 'pointer'
                }}
              >
                #{cls}
              </button>
            ))}
          </div>
        )}
      </div>
    </header>
  );
}
