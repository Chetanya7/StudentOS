// ===== Screen Navigation =====
function showScreen(screenId) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.getElementById(screenId).classList.add('active');
}

function navigateToDashboard() {
  showScreen('screen-dashboard');
}

// ===== Tab Switching =====
function switchTab(tabName) {
  // Update panels
  document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
  document.getElementById('tab-' + tabName).classList.add('active');

  // Update nav buttons
  document.querySelectorAll('.nav-item').forEach(btn => btn.classList.remove('active'));
  event.currentTarget.classList.add('active');
}

// ===== Theme Toggle =====
let isDark = false;

function toggleTheme() {
  isDark = !isDark;
  document.documentElement.setAttribute('data-theme', isDark ? 'dark' : 'light');
  document.getElementById('theme-icon').textContent = isDark ? 'light_mode' : 'dark_mode';
}

// Check system preference on load
if (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) {
  isDark = true;
  document.documentElement.setAttribute('data-theme', 'dark');
  document.getElementById('theme-icon').textContent = 'light_mode';
}
