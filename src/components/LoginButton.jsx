import { signInWithGoogle, signOut } from '../services/auth.js';

export function LoginButton({ user, onProfile }) {
  if (user) {
    return (
      <button
        onClick={onProfile}
        title={user.email}
        style={{
          display: 'flex', alignItems: 'center', gap: '8px',
          background: 'transparent', border: '1px solid var(--border)',
          borderRadius: '24px', padding: '4px 12px 4px 4px', cursor: 'pointer',
          color: 'var(--text)'
        }}
      >
        <img
          src={user.picture || 'https://i.pravatar.cc/40'}
          alt={user.name}
          style={{ width: '28px', height: '28px', borderRadius: '50%' }}
        />
        <span style={{ fontSize: '13px', fontWeight: 500 }}>{(user.name || '').split(' ')[0]}</span>
      </button>
    );
  }

  return (
    <button
      onClick={signInWithGoogle}
      style={{
        display: 'flex', alignItems: 'center', gap: '8px',
        background: 'var(--primary)', color: 'white', border: 'none',
        borderRadius: '24px', padding: '8px 16px', cursor: 'pointer',
        fontSize: '13px', fontWeight: 600
      }}
    >
      <i class="fab fa-google" />
      Sign in with Google
    </button>
  );
}

export { signOut };
