export function RoyalPage({ onClose }) {
  return (
    <div class="royal-page">
      <div class="royal-back-bar">
        <button class="royal-back-btn" onClick={onClose}><i class="fas fa-arrow-left" /> Back</button>
      </div>
      <div class="royal-hero">
        <div class="royal-crown"><i class="fas fa-crown" /></div>
        <div class="royal-avatar">
          <img src="https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=400&h=400&fit=crop" alt="Royal" />
        </div>
        <div class="royal-info">
          <h1 class="royal-name">Queen Elsee</h1>
          <div class="royal-title">👑 Royal Status • Supreme Pop • Crown Holder</div>
          <div class="royal-stats">
            <div class="royal-stat"><div class="royal-stat-value">#1</div><div class="royal-stat-label">Rank</div></div>
            <div class="royal-stat"><div class="royal-stat-value">24.5K</div><div class="royal-stat-label">Followers</div></div>
            <div class="royal-stat"><div class="royal-stat-value">1.2M</div><div class="royal-stat-label">Views</div></div>
            <div class="royal-stat"><div class="royal-stat-value">89</div><div class="royal-stat-label">Days</div></div>
          </div>
          <div class="royal-actions">
            <button class="royal-btn"><i class="fas fa-crown" /> Pay Tribute</button>
            <button class="royal-btn secondary"><i class="fas fa-gem" /> Send Gift</button>
            <button class="royal-btn secondary"><i class="fas fa-user-plus" /> Follow</button>
          </div>
        </div>
      </div>
      <div class="royalty-tier">
        <div class="tier-icon"><i class="fas fa-crown" /></div>
        <div class="tier-info">
          <h4>Supreme Royalty • Diamond Tier</h4>
          <p>Holder of the highest rank in the kingdom. Reigning champion for 89 consecutive days.</p>
        </div>
      </div>
      <div class="royalty-stats">
        <div class="royalty-stat"><div class="stat-value">89</div><div style="font-size:12px;color:var(--text-sec)">Reign Days</div></div>
        <div class="royalty-stat"><div class="stat-value">1,247</div><div style="font-size:12px;color:var(--text-sec)">Tributes</div></div>
        <div class="royalty-stat"><div class="stat-value">24.5K</div><div style="font-size:12px;color:var(--text-sec)">Subjects</div></div>
        <div class="royalty-stat"><div class="stat-value">#1</div><div style="font-size:12px;color:var(--text-sec)">Rank</div></div>
      </div>
    </div>
  );
}
