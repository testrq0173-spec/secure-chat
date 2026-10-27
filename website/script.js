// ==========================================================================
// BHAROSA MESSENGER - EDITORIAL TECH & MOTION ENGINE
// Features: Interactive Theme-Colored Spotlight Grid, Scroll-Based Reveals,
// 3D Parallax Tilt, Reading Progress Bar, and Zero-Knowledge Key Simulator
// ==========================================================================

document.addEventListener('DOMContentLoaded', () => {
  // 1. Interactive Theme-Colored Spotlight Grid Lines on Mouse Hover
  const root = document.documentElement;
  window.addEventListener('mousemove', (e) => {
    root.style.setProperty('--mouse-x', `${e.clientX}px`);
    root.style.setProperty('--mouse-y', `${e.clientY}px`);
  });

  // 2. Cursor Glow Follower (Tuned for Crisp Light Theme)
  const cursorGlow = document.getElementById('cursorGlow');
  if (cursorGlow) {
    let mouseX = window.innerWidth / 2;
    let mouseY = window.innerHeight / 2;
    let currentX = mouseX;
    let currentY = mouseY;

    window.addEventListener('mousemove', (e) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
    });

    function animateCursor() {
      currentX += (mouseX - currentX) * 0.14;
      currentY += (mouseY - currentY) * 0.14;
      cursorGlow.style.left = `${currentX}px`;
      cursorGlow.style.top = `${currentY}px`;
      requestAnimationFrame(animateCursor);
    }
    animateCursor();
  }

  // 3. Scroll Reading Progress Bar
  const progressBar = document.getElementById('scrollProgress');
  window.addEventListener('scroll', () => {
    if (progressBar) {
      const winScroll = document.documentElement.scrollTop || document.body.scrollTop;
      const height = document.documentElement.scrollHeight - document.documentElement.clientHeight;
      const scrolled = height > 0 ? (winScroll / height) * 100 : 0;
      progressBar.style.width = `${scrolled}%`;
    }
  }, { passive: true });

  // 4. Scroll-Based Reveal Animation Engine (IntersectionObserver)
  const revealElements = document.querySelectorAll('.reveal-on-scroll');
  if ('IntersectionObserver' in window) {
    const revealObserver = new IntersectionObserver((entries, observer) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, {
      root: null,
      rootMargin: '0px 0px -50px 0px',
      threshold: 0.1
    });

    revealElements.forEach(el => revealObserver.observe(el));
  } else {
    revealElements.forEach(el => el.classList.add('is-visible'));
  }

  // 5. Interactive 3D Tilt Parallax on Hero Smartphone Showcase
  const heroStage = document.getElementById('heroStage');
  const heroCard = document.getElementById('heroCard');
  const heroGlare = document.getElementById('heroGlare');
  const badgeLeft = document.getElementById('badgeLeft');
  const badgeRight = document.getElementById('badgeRight');
  const badgeTopRight = document.getElementById('badgeTopRight');

  if (heroStage && heroCard) {
    let tiltX = 0;
    let tiltY = 0;
    let targetTiltX = 0;
    let targetTiltY = 0;

    heroStage.addEventListener('mousemove', (e) => {
      const rect = heroStage.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      targetTiltX = ((y - centerY) / centerY) * -12;
      targetTiltY = ((x - centerX) / centerX) * 14;

      const glareX = (x / rect.width) * 100;
      const glareY = (y / rect.height) * 100;
      if (heroGlare) {
        heroGlare.style.setProperty('--glare-x', `${glareX}%`);
        heroGlare.style.setProperty('--glare-y', `${glareY}%`);
      }
    });

    heroStage.addEventListener('mouseleave', () => {
      targetTiltX = 0;
      targetTiltY = 0;
    });

    function update3DTilt() {
      tiltX += (targetTiltX - tiltX) * 0.1;
      tiltY += (targetTiltY - tiltY) * 0.1;

      heroCard.style.transform = `rotateX(${tiltX.toFixed(2)}deg) rotateY(${tiltY.toFixed(2)}deg) translateZ(0px)`;

      if (badgeLeft) {
        badgeLeft.style.transform = `translate3d(${-tiltY * 1.6}px, ${tiltX * 1.2}px, 50px)`;
      }
      if (badgeRight) {
        badgeRight.style.transform = `translate3d(${-tiltY * 2.0}px, ${tiltX * 1.5}px, 60px)`;
      }
      if (badgeTopRight) {
        badgeTopRight.style.transform = `translate3d(${-tiltY * 1.4}px, ${tiltX * 1.0}px, 40px)`;
      }

      requestAnimationFrame(update3DTilt);
    }
    update3DTilt();
  }

  // 6. Multi-Layer Scroll Parallax
  const orb1 = document.getElementById('orb1');
  const orb2 = document.getElementById('orb2');

  window.addEventListener('scroll', () => {
    const scrollY = window.scrollY;

    if (orb1) orb1.style.transform = `translateY(${scrollY * 0.12}px)`;
    if (orb2) orb2.style.transform = `translateY(${-scrollY * 0.1}px)`;
  }, { passive: true });

  // 7. Sticky Navbar on Scroll
  const navbar = document.querySelector('.navbar');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  }, { passive: true });

  // 8. FAQ Accordion Toggle
  const faqItems = document.querySelectorAll('.faq-item');
  faqItems.forEach(item => {
    const question = item.querySelector('.faq-question');
    question.addEventListener('click', () => {
      const isActive = item.classList.contains('active');
      faqItems.forEach(other => other.classList.remove('active'));
      if (!isActive) {
        item.classList.add('active');
      }
    });
  });

  // 9. Toast Notification Utility
  const toast = document.getElementById('toast');
  const toastText = document.getElementById('toast-text');
  let toastTimeout;

  function showToast(message, duration = 3800) {
    if (!toast) return;
    clearTimeout(toastTimeout);
    toastText.textContent = message;
    toast.classList.add('show');
    toastTimeout = setTimeout(() => {
      toast.classList.remove('show');
    }, duration);
  }

  // 10. iOS Coming Soon Trigger
  const iosButtons = document.querySelectorAll('.ios-trigger');
  iosButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      showToast('🍎 Apple iOS build is in internal TestFlight beta! Public App Store launch coming soon.');
    });
  });

  // 11. Download APK Trigger Toast
  const downloadBtns = document.querySelectorAll('.download-apk-btn');
  downloadBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      showToast('🚀 Downloading Bharosa Android APK (v1.0.0)...');
    });
  });

  // 12. Interactive Keypair Generator Simulator
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

  // 13. Smart Deep Link & Invite Handler
  const inviteModal = document.getElementById('inviteModal');
  const closeInviteModalBtn = document.getElementById('closeInviteModal');
  const modalOpenAppBtn = document.getElementById('modalOpenAppBtn');
  const inviterNameDisplay = document.getElementById('inviterNameDisplay');

  // Check URL query parameters or hash
  const urlParams = new URLSearchParams(window.location.search);
  const hash = window.location.hash;
  let inviteCode = urlParams.get('c') || urlParams.get('invite') || urlParams.get('data');

  if (!inviteCode && hash) {
    if (hash.includes('c=')) {
      inviteCode = hash.split('c=')[1].split('&')[0];
    } else if (hash.includes('invite=')) {
      inviteCode = hash.split('invite=')[1].split('&')[0];
    } else if (hash.startsWith('#')) {
      const potential = hash.substring(1);
      if (potential.length > 20) inviteCode = potential;
    }
  }

  function openInviteModal() {
    if (inviteModal) {
      inviteModal.classList.add('show');
    }
  }

  function closeInviteModal() {
    if (inviteModal) {
      inviteModal.classList.remove('show');
    }
  }

  if (closeInviteModalBtn) {
    closeInviteModalBtn.addEventListener('click', closeInviteModal);
  }

  if (inviteModal) {
    inviteModal.addEventListener('click', (e) => {
      if (e.target === inviteModal) {
        closeInviteModal();
      }
    });
  }

  if (inviteCode) {
    // Try to decode inviter's display name from payload
    let inviterName = 'A friend';
    try {
      let norm = inviteCode.trim();
      while (norm.length % 4 !== 0) norm += '=';
      const decodedStr = atob(norm.replace(/-/g, '+').replace(/_/g, '/'));
      const parsed = JSON.parse(decodedStr);
      if (parsed && parsed.name) {
        inviterName = parsed.name;
      }
    } catch (_) {}

    if (inviterNameDisplay) {
      inviterNameDisplay.textContent = inviterName;
    }

    const appDeepLink = `bharosa://connect?data=${encodeURIComponent(inviteCode)}`;

    if (modalOpenAppBtn) {
      modalOpenAppBtn.addEventListener('click', () => {
        window.location.href = appDeepLink;
      });
    }

    // Attempt to open the app if installed
    let appOpened = false;

    const markAppOpened = () => {
      appOpened = true;
    };

    window.addEventListener('blur', markAppOpened);
    document.addEventListener('visibilitychange', () => {
      if (document.hidden) markAppOpened();
    });

    // Fire deep link to attempt launching installed app
    window.location.href = appDeepLink;

    // After 1.4s, if user is still on this webpage, app is not installed
    setTimeout(() => {
      if (!appOpened && !document.hidden) {
        // Smoothly scroll down to the download section
        const downloadSection = document.getElementById('download');
        if (downloadSection) {
          downloadSection.scrollIntoView({ behavior: 'smooth' });
        }
        // Show the download required popup modal
        openInviteModal();
      }
    }, 1400);
  }
});
