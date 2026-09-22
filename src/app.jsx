import { Component } from 'preact';
import { Header } from './components/Header.jsx';
import { Footer } from './components/Footer.jsx';
import { PinGrid } from './components/PinGrid.jsx';
import { PinDetail } from './components/PinDetail.jsx';
import { UploadModal } from './components/UploadModal.jsx';
import { ProfileModal } from './components/ProfileModal.jsx';
import { LoadingSpinner } from './components/LoadingSpinner.jsx';
import { RoyalPage } from './components/RoyalPage.jsx';
import { usePins } from './hooks/usePins.js';
import { initAI } from './services/ai.js';
import { getCurrentUser, signInWithGoogle } from './services/auth.js';

const STORIES = [
  { id: 'own', username: 'Your Story', avatar: 'https://i.pravatar.cc/150?img=12', isAdd: true },
  { id: 'sophia', username: 'Sophia', avatar: 'https://i.pravatar.cc/150?img=1' },
  { id: 'emma', username: 'Emma', avatar: 'https://i.pravatar.cc/150?img=5' },
  { id: 'olivia', username: 'Olivia', avatar: 'https://i.pravatar.cc/150?img=6' },
  { id: 'royal', username: 'Queen Elsee', avatar: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&h=200&fit=crop', royal: true },
  { id: 'ava', username: 'Ava', avatar: 'https://i.pravatar.cc/150?img=7' },
  { id: 'isabella', username: 'Isabella', avatar: 'https://i.pravatar.cc/150?img=8' }
];

export class App extends Component {
  constructor() {
    super();
    this.state = {
      pins: [],
      loading: true,
      selectedPin: null,
      showUpload: false,
      showProfile: false,
      searchTerm: '',
      filterCategory: 'all',
      selectedClass: '',
      classes: [],
      darkMode: false,
      aiReady: false,
      aiProgress: 0,
      aiStatus: '',
      columns: 4,
      activeTab: 'home',
      showRoyalPage: false,
      user: null,
      userLoading: true
    };
  }

  async componentDidMount() {
    const saved = localStorage.getItem('darkMode');
    const isDark = saved === 'true';
    if (isDark) document.documentElement.setAttribute('data-theme', 'dark');
    this.setState({ darkMode: isDark });

    this.updateColumns();
    window.addEventListener('resize', this.updateColumns);

    window._onProgress = (progress) => {
      if (progress === 100) this.setState({ aiProgress: 100, aiStatus: 'AI Ready!' });
      else this.setState({ aiProgress: progress, aiStatus: `Downloading model... ${progress}%` });
    };

    // Get current user first (needed before saving)
    const user = await getCurrentUser();
    this.setState({ user, userLoading: false });

    // Load pins + AI in parallel
    this.loadPins();
    this.loadClasses();
    initAI().then(success => {
      this.setState({
        aiReady: success,
        aiProgress: success ? 100 : 0,
        aiStatus: success ? 'AI Ready!' : 'AI unavailable - using basic mode'
      });
    });
  }

  componentWillUnmount() {
    window.removeEventListener('resize', this.updateColumns);
  }

  updateColumns = () => {
    const w = window.innerWidth;
    let columns = 4;
    if (w < 480) columns = 2;
    else if (w < 768) columns = 2;
    else if (w < 1024) columns = 3;
    else if (w < 1400) columns = 4;
    else columns = 5;
    this.setState({ columns });
  };

  loadPins = async () => {
    try {
      const pins = await usePins.getAll();
      this.setState({ pins, loading: false });
    } catch (e) {
      console.error('Failed to load pins:', e);
      this.setState({ pins: [], loading: false });
    }
  };

  loadClasses = async () => {
    try {
      const classes = await usePins.getClasses();
      this.setState({ classes });
    } catch {}
  };

  handleSavePin = async (pinData) => {
    if (!this.state.user) {
      alert('Please sign in with Google to save pins to your Drive.');
      signInWithGoogle();
      return;
    }
    await usePins.add(pinData);
    await this.loadPins();
    await this.loadClasses();
    this.setState({ showUpload: false, activeTab: 'home' });
  };

  handleDeletePin = async (id) => {
    if (!confirm('Delete this pin? (Also removes the file from your Google Drive)')) return;
    try {
      await usePins.delete(id);
      this.setState({ selectedPin: null });
      await this.loadPins();
      await this.loadClasses();
    } catch (e) {
      alert('Delete failed: ' + e.message);
    }
  };

  handleUpdatePin = async (id, data) => {
    try {
      await usePins.update(id, data);
      if (this.state.selectedPin?.id === id) {
        this.setState({ selectedPin: { ...this.state.selectedPin, ...data } });
      }
      await this.loadPins();
      await this.loadClasses();
    } catch (e) {
      console.error('Update failed:', e);
    }
  };

  handleClearAll = async () => {
    alert('Clear All is disabled — pins live in Supabase now. Delete them individually.');
  };

  toggleTheme = () => {
    const newDark = !this.state.darkMode;
    this.setState({ darkMode: newDark });
    localStorage.setItem('darkMode', newDark);
    document.documentElement.setAttribute('data-theme', newDark ? 'dark' : '');
  };

  handleGoHome = () => {
    this.setState({
      activeTab: 'home', selectedPin: null, showUpload: false,
      showProfile: false, filterCategory: 'all', selectedClass: '', searchTerm: ''
    });
  };

  handleOpenUpload = () => {
    if (!this.state.user) {
      if (confirm('Sign in with Google to upload pins to your Drive?')) {
        signInWithGoogle();
      }
      return;
    }
    this.setState({ showUpload: true, activeTab: 'upload' });
  };

  handleOpenProfile = () => {
    this.setState({ showProfile: true, activeTab: 'profile' });
  };

  handleStoryClick = (story) => {
    if (story.isAdd) {
      this.handleOpenUpload();
      return;
    }
    this.setState({ showRoyalPage: true });
  };

  render() {
    const {
      loading, selectedPin, showUpload, showProfile, searchTerm,
      filterCategory, selectedClass, classes, darkMode, aiReady,
      aiProgress, aiStatus, columns, pins, activeTab,
      showRoyalPage, user
    } = this.state;

    if (showRoyalPage) {
      return <RoyalPage onClose={() => this.setState({ showRoyalPage: false })} />;
    }

    if (loading) {
      return <LoadingSpinner aiStatus={aiStatus} aiProgress={aiProgress} />;
    }

    const allCategories = ['all', 'Nature', 'ass', 'milf', 'soles'];
    const filteredPins = usePins.filter(pins, searchTerm, filterCategory, selectedClass);

    return (
      <div style={{ minHeight: '100vh', background: 'var(--bg)' }}>
        <Header
          aiReady={aiReady}
          searchTerm={searchTerm}
          filterCategory={filterCategory}
          selectedClass={selectedClass}
          classes={classes}
          allCategories={allCategories}
          onSearchChange={(value) => this.setState({ searchTerm: value })}
          onFilterChange={(value) => this.setState({ filterCategory: value })}
          onClassChange={(value) => this.setState({ selectedClass: value })}
          onReset={this.handleGoHome}
          user={user}
          onProfile={this.handleOpenProfile}
        />

        <div style={{ maxWidth: '1400px', margin: '0 auto', padding: '0 16px 90px' }}>
          <div className="stories-row">
            {STORIES.map((story) => (
              <div key={story.id} className="story-item" onClick={() => this.handleStoryClick(story)}>
                <div className={
                  'story-avatar' +
                  (story.isAdd ? ' add-story' : '') +
                  (story.royal ? ' royal-ring' : '')
                }>
                  {story.isAdd ? <i className="fas fa-plus" /> : <img src={story.avatar} alt={story.username} />}
                </div>
                <div className="story-username">{story.username}</div>
              </div>
            ))}
          </div>

          <PinGrid
            pins={filteredPins}
            columns={columns}
            onPinClick={(pin) => this.setState({ selectedPin: pin })}
          />
        </div>

        {selectedPin && (
          <PinDetail
            pin={selectedPin}
            allPins={pins}
            aiReady={aiReady}
            onClose={() => this.setState({ selectedPin: null })}
            onDelete={this.handleDeletePin}
            onUpdate={this.handleUpdatePin}
            onSelectPin={(pin) => this.setState({ selectedPin: pin })}
          />
        )}

        {showUpload && (
          <UploadModal
            aiReady={aiReady}
            classes={classes}
            categories={allCategories.filter(c => c !== 'all')}
            onClose={() => this.setState({ showUpload: false, activeTab: 'home' })}
            onSave={this.handleSavePin}
          />
        )}

        {showProfile && (
          <ProfileModal
            pins={pins}
            classes={classes}
            aiReady={aiReady}
            darkMode={darkMode}
            user={user}
            onClose={() => this.setState({ showProfile: false, activeTab: 'home' })}
            onClearAll={this.handleClearAll}
            onToggleTheme={this.toggleTheme}
          />
        )}

        <Footer
          activeTab={activeTab}
          onHome={this.handleGoHome}
          onUpload={this.handleOpenUpload}
          onProfile={this.handleOpenProfile}
        />
      </div>
    );
  }
}
