// ==========================================================================
// BHAROSA MESSENGER - CLIENT INTERACTIONS & MOTION ENGINE
// ==========================================================================

document.addEventListener('DOMContentLoaded', () => {
  // 1. Sticky Navbar on Scroll
  const navbar = document.querySelector('.navbar');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  });

  // 2. Interactive Spotlight Card Glow on Mouse Move
  const cards = document.querySelectorAll('.bento-card, .stat-card, .arch-step-card');
  cards.forEach(card => {
    card.addEventListener('mousemove', (e) => {
      const rect = card.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      card.style.setProperty('--mouse-x', `${x}px`);
      card.style.setProperty('--mouse-y', `${y}px`);
    });
  });

  // 3. FAQ Accordion Toggle
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    question.addEventListener('click', () => {
      const isActive = item.classList.contains('active');
      // Close all other items
      faqItems.forEach(other => other.classList.remove('active'));
      if (!isActive) {
        item.classList.add('active');
      }
    });
  });

  // 4. Toast Notification Utility
  const toast = document.getElementById('toast');
  const toastText = document.getElementById('toast-text');
  let toastTimeout;

  function showToast(message, duration = 3500) {
    if (!toast) return;
    clearTimeout(toastTimeout);
    toastText.textContent = message;
    toast.classList.add('show');
    toastTimeout = setTimeout(() => {
      toast.classList.remove('show');
    }, duration);
  }

  // 5. iOS Coming Soon Trigger
  const iosButtons = document.querySelectorAll('.ios-trigger');
  iosButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      showToast('🍎 iOS version is currently in internal TestFlight beta! Public App Store release coming soon.');
    });
  });

  // 6. Download APK Trigger Toast
  const downloadBtns = document.querySelectorAll('.download-apk-btn');
  downloadBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      showToast('🚀 Downloading Bharosa Android APK (v1.0.0)...');
    });
  });

  // 7. Interactive Keypair Generator Simulator
  const regBtn = document.getElementById('regenerate-keys-btn');
  const pubKeyEl = document.getElementById('sim-pub-key');
  const privKeyEl = document.getElementById('sim-priv-key');
  const queueTokenEl = document.getElementById('sim-queue-token');
  const safetyCodeEl = document.getElementById('sim-safety-code');

  function randomHex(length) {
    const chars = '0123456789abcdef';
    let result = '';
    for (let i = 0; i < length; i++) {
      result += chars[Math.floor(Math.random() * chars.length)];
    }
    return result;
  }

  if (regBtn) {
    regBtn.addEventListener('click', () => {
      regBtn.disabled = true;
      regBtn.textContent = 'Generating...';

      setTimeout(() => {
        if (pubKeyEl) pubKeyEl.textContent = `0x${randomHex(8)}...${randomHex(4)}`;
        if (privKeyEl) privKeyEl.textContent = 'Vault-Encrypted (Hardware Keystore)';
        if (queueTokenEl) queueTokenEl.textContent = `q_${randomHex(12)}`;
        if (safetyCodeEl) {
          const num1 = Math.floor(100 + Math.random() * 900);
          const num2 = Math.floor(100 + Math.random() * 900);
          safetyCodeEl.textContent = `${num1}-${num2} (Double Ratchet Verified)`;
        }
        regBtn.disabled = false;
        regBtn.textContent = 'Regenerate Ephemeral Keys';
        showToast('✨ New Double Ratchet ephemeral keypair generated!');
      }, 350);
    });
  }
});
