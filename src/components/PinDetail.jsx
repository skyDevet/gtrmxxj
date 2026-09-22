import { Component, createRef } from 'preact';
import { cosineSimilarity } from '../services/ai.js';

export class PinDetail extends Component {
  constructor(props) {
    super(props);
    this.state = {
      isLiked: false,
      comment: '',
      saved: props.pin?.saved || false,
      similarPins: [],
      showCommentInput: false,
      searching: false
    };
    this.commentInputRef = createRef();
    this.similarSectionRef = createRef();
  }

  componentDidMount() {
    this.findSimilar();
  }

  componentDidUpdate(prevProps) {
    if (prevProps.pin?.id !== this.props.pin?.id) {
      this.setState({
        isLiked: false,
        saved: this.props.pin?.saved || false,
        showCommentInput: false
      });
      this.findSimilar();
    }
  }

  findSimilar = () => {
    const { pin, allPins, aiReady } = this.props;
    this.setState({ searching: true });

    if (aiReady && pin.features) {
      this.setState({
        similarPins: allPins
          .filter(p => p.id !== pin.id && p.features)
          .map(p => ({ ...p, similarity: cosineSimilarity(pin.features, p.features) }))
          .filter(p => p.similarity > 0.5)
          .sort((a, b) => b.similarity - a.similarity)
          .slice(0, 8),
        searching: false
      });
    } else {
      this.setState({
        similarPins: allPins
          .filter(p => p.id !== pin.id && (p.category === pin.category || p.class === pin.class))
          .slice(0, 8),
        searching: false
      });
    }
  };

  handleSearchSimilar = () => {
    this.findSimilar();
    if (this.similarSectionRef.current) {
      this.similarSectionRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  };

  handleLike = () => {
    const newLiked = !this.state.isLiked;
    this.setState({ isLiked: newLiked });
    this.props.onUpdate(this.props.pin.id, {
      likes: (this.props.pin.likes || 0) + (newLiked ? 1 : -1)
    });
  };

  handleSave = () => {
    const newSaved = !this.state.saved;
    this.setState({ saved: newSaved });
    this.props.onUpdate(this.props.pin.id, { saved: newSaved });
  };

  toggleCommentInput = () => {
    this.setState(prev => ({ showCommentInput: !prev.showCommentInput }), () => {
      if (this.state.showCommentInput && this.commentInputRef.current) {
        this.commentInputRef.current.focus();
      }
    });
  };

  handleComment = () => {
    const { comment } = this.state;
    if (!comment.trim()) return;
    this.props.onUpdate(this.props.pin.id, {
      comments: [...(this.props.pin.comments || []), { text: comment, timestamp: Date.now() }]
    });
    this.setState({ comment: '' });
  };

  render() {
    const { pin, onClose, onDelete, onSelectPin, aiReady } = this.props;
    const { isLiked, comment, saved, similarPins, showCommentInput, searching } = this.state;

    if (!pin) return null;

    return (
      <div
        style={{
          position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(0,0,0,0.8)', zIndex: 1000,
          display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '20px'
        }}
        onClick={onClose}
      >
        <div
          style={{
            background: 'var(--card)', borderRadius: '16px', maxWidth: '700px',
            width: '100%', maxHeight: '90vh', overflow: 'auto',
            position: 'relative', display: 'flex', flexDirection: 'column'
          }}
          onClick={(e) => e.stopPropagation()}
        >
          {/* Image + overlaid buttons */}
          <div style={{ position: 'relative', width: '100%', background: 'var(--bg)' }}>
            <button
              style={{
                position: 'absolute', top: '12px', right: '12px',
                background: 'rgba(0,0,0,0.5)', border: 'none', color: 'white',
                width: '36px', height: '36px', borderRadius: '50%', cursor: 'pointer',
                fontSize: '16px', zIndex: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'center'
              }}
              onClick={onClose}
            >
              <i class="fas fa-times" />
            </button>

            <img
              src={pin.image || pin.thumbnail}
              alt={pin.title}
              style={{
                width: '100%', maxHeight: '65vh', objectFit: 'cover',
                display: 'block', borderRadius: '16px 16px 0 0'
              }}
              onError={(e) => {
                // Fallback to Google Drive direct export URL if the primary fails
                if (pin.driveFileId) {
                  e.target.src = `https://drive.google.com/uc?export=download&id=${pin.driveFileId}`;
                }
              }}
            />

            <button
              onClick={this.handleSearchSimilar}
              disabled={searching}
              style={{
                position: 'absolute', bottom: '16px', right: '16px',
                background: 'white', color: '#111', border: 'none', borderRadius: '24px',
                padding: '10px 16px', display: 'flex', alignItems: 'center', gap: '8px',
                boxShadow: '0 2px 10px rgba(0,0,0,0.35)',
                cursor: searching ? 'not-allowed' : 'pointer',
                fontWeight: 600, fontSize: '13px', opacity: searching ? 0.7 : 1
              }}
            >
              <i class={`fas ${searching ? 'fa-spinner fa-pulse' : 'fa-search'}`} />
              {searching ? 'Searching...' : ''}
            </button>
          </div>

          <div style={{ padding: '20px', overflow: 'auto' }}>
            {/* Title row */}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '10px', marginBottom: '10px' }}>
              <h2 style={{
                fontSize: '18px', margin: 0, color: 'var(--text)', flex: 1, minWidth: 0,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'
              }}>{pin.title}</h2>

              <div style={{ display: 'flex', alignItems: 'center', gap: '12px', flexShrink: 0 }}>
                <button
                  style={{
                    background: 'none', border: 'none',
                    color: isLiked ? 'var(--primary)' : 'var(--text-sec)',
                    cursor: 'pointer', fontSize: '15px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.handleLike}
                >
                  <i class={`${isLiked ? 'fas' : 'far'} fa-heart`} /> {pin.likes || 0}
                </button>

                <button
                  style={{
                    background: 'none', border: 'none',
                    color: showCommentInput ? 'var(--primary)' : 'var(--text-sec)',
                    cursor: 'pointer', fontSize: '15px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.toggleCommentInput}
                >
                  <i class="far fa-comment" /> {(pin.comments || []).length}
                </button>

                <button
                  style={{
                    background: saved ? 'var(--primary)' : 'transparent',
                    border: `1px solid ${saved ? 'var(--primary)' : 'var(--border)'}`,
                    color: saved ? 'white' : 'var(--text)',
                    cursor: 'pointer', fontSize: '13px', fontWeight: 600,
                    padding: '6px 14px', borderRadius: '18px',
                    display: 'flex', alignItems: 'center', gap: '5px'
                  }}
                  onClick={this.handleSave}
                >
                  <i class={`${saved ? 'fas' : 'far'} fa-bookmark`} /> Save
                </button>

                <button
                  style={{ background: 'none', border: 'none', color: '#ef4444', cursor: 'pointer', fontSize: '15px' }}
                  onClick={() => onDelete(pin.id)}
                >
                  <i class="fas fa-trash" />
                </button>
              </div>
            </div>

            {/* Tags */}
            <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', marginBottom: '12px' }}>
              <span style={{ background: 'var(--border)', padding: '4px 12px', borderRadius: '16px', fontSize: '13px', color: 'var(--text-sec)' }}>{pin.category}</span>
              {pin.class && <span style={{ background: 'var(--border)', padding: '4px 12px', borderRadius: '16px', fontSize: '13px', color: 'var(--text-sec)' }}>#{pin.class}</span>}
              {pin.features && <span class="ai-badge" style={{ padding: '4px 12px', borderRadius: '16px', fontSize: '13px', background: 'var(--primary)', color: 'white' }}>🤖 AI</span>}
            </div>

            {/* Owner info (new) */}
            {pin.owner && (
              <div style={{
                display: 'flex', alignItems: 'center', gap: '8px',
                marginBottom: '12px', padding: '8px 12px',
                background: 'var(--bg)', borderRadius: '12px'
              }}>
                <img
                  src={pin.owner.picture || 'https://i.pravatar.cc/40'}
                  alt={pin.owner.name || 'User'}
                  style={{ width: '28px', height: '28px', borderRadius: '50%' }}
                />
                <div style={{ fontSize: '13px', color: 'var(--text)' }}>
                  <span style={{ fontWeight: 600 }}>{pin.owner.name || 'Unknown'}</span>
                  {pin.owner.email && <span style={{ color: 'var(--text-sec)', marginLeft: '6px' }}>· {pin.owner.email}</span>}
                </div>
              </div>
            )}

            {pin.description && (
              <p style={{ color: 'var(--text-sec)', lineHeight: 1.6, marginBottom: '16px' }}>{pin.description}</p>
            )}

            {/* Comment input */}
            {showCommentInput && (
              <div style={{ display: 'flex', gap: '8px', marginBottom: '16px' }}>
                <input
                  ref={this.commentInputRef}
                  type="text"
                  placeholder="Add comment..."
                  value={comment}
                  onInput={(e) => this.setState({ comment: e.target.value })}
                  onKeyPress={(e) => { if (e.key === 'Enter') this.handleComment(); }}
                  style={{
                    flex: 1, padding: '10px 14px', borderRadius: '20px',
                    border: '1px solid var(--border)', background: 'var(--bg)',
                    color: 'var(--text)', outline: 'none'
                  }}
                />
                <button
                  onClick={this.handleComment}
                  disabled={!comment.trim()}
                  style={{
                    width: '40px', height: '40px', borderRadius: '50%',
                    background: 'var(--primary)', color: 'white', border: 'none',
                    cursor: 'pointer', display: 'flex',
                    alignItems: 'center', justifyContent: 'center', flexShrink: 0
                  }}
                >
                  <i class="fas fa-paper-plane" />
                </button>
              </div>
            )}

            {/* Comments list */}
            <div style={{ marginBottom: '8px' }}>
              <h4 style={{ marginBottom: '12px', color: 'var(--text)' }}>Comments ({(pin.comments || []).length})</h4>
              <div style={{ maxHeight: '200px', overflow: 'auto', marginBottom: '12px' }}>
                {(pin.comments || []).length === 0 ? (
                  <p style={{ color: 'var(--text-sec)', textAlign: 'center' }}>No comments</p>
                ) : (
                  (pin.comments || []).map((c, i) => (
                    <div key={i} style={{ display: 'flex', gap: '8px', padding: '8px 0', borderBottom: '1px solid var(--border)' }}>
                      <div style={{
                        width: '28px', height: '28px', borderRadius: '50%',
                        background: 'var(--border)', display: 'flex',
                        alignItems: 'center', justifyContent: 'center', flexShrink: 0
                      }}>
                        <i class="fas fa-user" style={{ fontSize: '12px', color: 'var(--text-sec)' }} />
                      </div>
                      <div style={{ flex: 1 }}>
                        <p style={{ fontSize: '14px', color: 'var(--text)' }}>{c.text}</p>
                        <span style={{ fontSize: '11px', color: 'var(--text-sec)' }}>{new Date(c.timestamp).toLocaleString()}</span>
                      </div>
                    </div>
                  ))
                )}
              </div>
            </div>

            {/* Similar pins */}
            {similarPins.length > 0 && (
              <div ref={this.similarSectionRef} style={{ marginTop: '20px' }}>
                <h4 style={{ marginBottom: '12px', color: 'var(--text)' }}>
                  {aiReady && pin.features ? '🤖 AI Similar' : '📂 Similar'}
                </h4>
                <div style={{ columnCount: 2, columnGap: '10px' }}>
                  {similarPins.map(p => (
                    <div
                      key={p.id}
                      style={{
                        breakInside: 'avoid', marginBottom: '10px',
                        borderRadius: '10px', overflow: 'hidden',
                        background: 'var(--bg)', cursor: 'pointer', position: 'relative'
                      }}
                      onClick={() => onSelectPin(p)}
                    >
                      <img
                        src={p.thumbnail || p.image}
                        alt={p.title}
                        style={{ width: '100%', display: 'block', objectFit: 'cover' }}
                        onError={(e) => {
                          if (p.driveFileId) {
                            e.target.src = `https://drive.google.com/uc?export=download&id=${p.driveFileId}`;
                          }
                        }}
                      />
                      <div style={{
                        position: 'absolute', bottom: 0, left: 0, right: 0,
                        padding: '8px',
                        background: 'linear-gradient(to top, rgba(0,0,0,0.65), transparent)',
                        color: 'white'
                      }}>
                        <span style={{
                          display: 'block', fontSize: '12px',
                          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap'
                        }}>{p.title}</span>
                        {p.similarity && (
                          <span style={{ fontSize: '10px', opacity: 0.85 }}>
                            {Math.round(p.similarity * 100)}% match
                          </span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }
}
