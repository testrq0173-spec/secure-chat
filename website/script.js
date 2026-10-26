// ==========================================================================
// BHAROSA MESSENGER - MOTIONSITES-STYLE PARALLAX & MOTION ENGINE
// ==========================================================================

document.addEventListener('DOMContentLoaded', () => {
  // 1. Cursor Glow Spotlight Follower
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
      // Smooth interpolation (lerp)
      currentX += (mouseX - currentX) * 0.12;
      currentY += (mouseY - currentY) * 0.12;
      cursorGlow.style.left = `${currentX}px`;
      cursorGlow.style.top = `${currentY}px`;
      requestAnimationFrame(animateCursor);
    }
    animateCursor();
  }

  // 2. Interactive 3D Tilt Parallax on Hero Showcase
  const heroStage = document.getElementById('heroStage');
  const heroCard = document.getElementById('heroCard');
  const heroGlare = document.getElementById('heroGlare');
  const badgeLeft = document.getElementById('badgeLeft');
  const badgeRight = document.getElementById('badgeRight');
  const badgeTopRight = document.getElementById('badgeTopRight');

  if (heroStage && heroCard) {
    let isHovering = false;
    let tiltX = 0;
    let tiltY = 0;
    let targetTiltX = 0;
    let targetTiltY = 0;

    heroStage.addEventListener('mouseenter', () => {
      isHovering = true;
    });

    heroStage.addEventListener('mousemove', (e) => {
      const rect = heroStage.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      const centerX = rect.width / 2;
      const centerY = rect.height / 2;

      // Calculate tilt angles (clamped for natural feel)
      targetTiltX = ((y - centerY) / centerY) * -14;
      targetTiltY = ((x - centerX) / centerX) * 16;

      // Update glare reflection position
      const glareX = (x / rect.width) * 100;
      const glareY = (y / rect.height) * 100;
      if (heroGlare) {
        heroGlare.style.setProperty('--glare-x', `${glareX}%`);
        heroGlare.style.setProperty('--glare-y', `${glareY}%`);
      }
    });

    heroStage.addEventListener('mouseleave', () => {
      isHovering = false;
      targetTiltX = 0;
      targetTiltY = 0;
    });

    function update3DTilt() {
      // Smooth spring interpolation
      tiltX += (targetTiltX - tiltX) * 0.1;
      tiltY += (targetTiltY - tiltY) * 0.1;

      heroCard.style.transform = `rotateX(${tiltX.toFixed(2)}deg) rotateY(${tiltY.toFixed(2)}deg) translateZ(0px)`;

      // Parallax floating capsules in opposite direction for maximum depth illusion!
      if (badgeLeft) {
        badgeLeft.style.transform = `translate3d(${-tiltY * 1.8}px, ${tiltX * 1.4}px, 60px)`;
      }
      if (badgeRight) {
        badgeRight.style.transform = `translate3d(${-tiltY * 2.2}px, ${tiltX * 1.8}px, 80px)`;
      }
      if (badgeTopRight) {
        badgeTopRight.style.transform = `translate3d(${-tiltY * 1.5}px, ${tiltX * 1.2}px, 50px)`;
      }

      requestAnimationFrame(update3DTilt);
    }
    update3DTilt();
  }

  // 3. Multi-Layer Scroll Parallax Engine
  const orb1 = document.getElementById('orb1');
  const orb2 = document.getElementById('orb2');
  const heroTitle = document.getElementById('heroTitle');
  const heroSubtitle = document.getElementById('heroSubtitle');
  const heroBadge = document.getElementById('heroBadge');

  window.addEventListener('scroll', () => {
    const scrollY = window.scrollY;

    // Ambient orbs parallax
    if (orb1) orb1.style.transform = `translateY(${scrollY * 0.15}px)`;
    if (orb2) orb2.style.transform = `translateY(${-scrollY * 0.12}px)`;

    // Hero title gentle parallax drift
    if (heroTitle && scrollY < 800) {
      heroTitle.style.transform = `translateY(${scrollY * 0.18}px)`;
      heroTitle.style.opacity = `${Math.max(0, 1 - scrollY / 700)}`;
    }
    if (heroSubtitle && scrollY < 800) {
      heroSubtitle.style.transform = `translateY(${scrollY * 0.12}px)`;
      heroSubtitle.style.opacity = `${Math.max(0, 1 - scrollY / 650)}`;
    }
    if (heroBadge && scrollY < 800) {
      heroBadge.style.transform = `translateY(${scrollY * 0.22}px)`;
    }
  }, { passive: true });

  // 4. Sticky Navbar on Scroll
  const navbar = document.querySelector('.navbar');
  window.addEventListener('scroll', () => {
    if (window.scrollY > 40) {
      navbar.classList.add('scrolled');
    } else {
      navbar.classList.remove('scrolled');
    }
  }, { passive: true });

  // 5. Interactive Spotlight Card Glow on Mouse Move
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

  // 6. FAQ Accordion Toggle
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

  // 7. Toast Notification Utility
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

  // 8. iOS Coming Soon Trigger
  const iosButtons = document.querySelectorAll('.ios-trigger');
  iosButtons.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.preventDefault();
      showToast('🍎 Apple iOS build is in internal TestFlight beta! Public App Store launch coming soon.');
    });
  });

  // 9. Download APK Trigger Toast
  const downloadBtns = document.querySelectorAll('.download-apk-btn');
  downloadBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      showToast('🚀 Downloading Bharosa Android APK (v1.0.0)...');
    });
  });

  // 10. Interactive Keypair Generator Simulator
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
