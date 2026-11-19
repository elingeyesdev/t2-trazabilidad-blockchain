<script>
(function () {
    'use strict';

    var sidebar  = document.getElementById('agSidebar');
    var main     = document.getElementById('agMain');
    var toggle   = document.getElementById('agToggle');
    var overlay  = document.getElementById('agOverlay');
    var userBtn  = document.getElementById('agUserBtn');
    var userDrop = document.getElementById('agUserDropdown');
    var fullBtn  = document.getElementById('agFullscreen');

    // ── Sidebar toggle (desktop: mini / mobile: open) ─────────────────
    var isMobile = window.innerWidth <= 768;

    function refreshState() {
        isMobile = window.innerWidth <= 768;
        if (!isMobile) {
            sidebar.classList.remove('mobile-open');
            overlay.classList.remove('show');
        }
        if (toggle) toggle.setAttribute('aria-expanded', String(isMobile ? sidebar.classList.contains('mobile-open') : !sidebar.classList.contains('mini')));
    }

    window.addEventListener('resize', refreshState);
    refreshState();

    if (toggle) {
        toggle.addEventListener('click', function () {
            if (isMobile) {
                sidebar.classList.toggle('mobile-open');
                overlay.classList.toggle('show');
                main.classList.remove('mini');
            } else {
                var mini = sidebar.classList.toggle('mini');
                main.classList.toggle('mini', mini);
            }
            toggle.setAttribute('aria-expanded', String(isMobile ? sidebar.classList.contains('mobile-open') : !sidebar.classList.contains('mini')));
        });
    }

    if (overlay) {
        overlay.addEventListener('click', function () {
            sidebar.classList.remove('mobile-open');
            overlay.classList.remove('show');
            toggle?.setAttribute('aria-expanded', 'false');
        });
    }

    // ── Sub-menus ─────────────────────────────────────────────────────
    var sbNav = document.querySelector('.ag-sb-nav');
    var sbScrollKey = 'agSbNavScroll';

    if (sbNav) {
        function restoreSbScroll() {
            try {
                var savedScroll = sessionStorage.getItem(sbScrollKey);
                if (savedScroll !== null) {
                    sbNav.scrollTop = parseInt(savedScroll, 10) || 0;
                }
            } catch (err) {}
        }

        restoreSbScroll();
        requestAnimationFrame(function () {
            restoreSbScroll();
        });

        sbNav.addEventListener('scroll', function () {
            try { sessionStorage.setItem(sbScrollKey, String(sbNav.scrollTop)); } catch (err) {}
        }, { passive: true });

        sbNav.querySelectorAll('a[href]:not([href="#"]):not([href=""])').forEach(function (link) {
            if (link.getAttribute('href') === 'javascript:void(0)') return;
            link.addEventListener('click', function () {
                try { sessionStorage.setItem(sbScrollKey, String(sbNav.scrollTop)); } catch (err) {}
            });
        });
    }

    document.querySelectorAll('[data-toggle-sub]').forEach(function (trigger) {
        trigger.setAttribute('aria-expanded', String(trigger.classList.contains('group-open')));
        trigger.setAttribute('aria-controls', trigger.getAttribute('data-toggle-sub'));
        trigger.addEventListener('click', function (e) {
            e.preventDefault();
            e.stopPropagation();
            var targetId = this.getAttribute('data-toggle-sub');
            var sub = document.getElementById(targetId);
            if (!sub) return;

            var navScrollBefore = sbNav ? sbNav.scrollTop : 0;
            var isOpen = sub.classList.contains('open');

            sub.classList.toggle('open', !isOpen);
            trigger.classList.toggle('group-open', !isOpen);
            trigger.setAttribute('aria-expanded', String(!isOpen));

            if (sbNav) {
                sbNav.scrollTop = navScrollBefore;
            }
        });
    });

    // ── User dropdown ──────────────────────────────────────────────────
    if (userBtn && userDrop) {
        userBtn.addEventListener('click', function (e) {
            e.stopPropagation();
            userDrop.classList.toggle('show');
            userBtn.setAttribute('aria-expanded', String(userDrop.classList.contains('show')));
        });

        document.addEventListener('click', function () {
            userDrop.classList.remove('show');
            userBtn.setAttribute('aria-expanded', 'false');
        });

        userDrop.addEventListener('click', function (e) {
            e.stopPropagation();
        });
    }

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (sidebar.classList.contains('mobile-open')) {
            sidebar.classList.remove('mobile-open');
            overlay.classList.remove('show');
            toggle?.setAttribute('aria-expanded', 'false');
            toggle?.focus();
        }
        if (userDrop?.classList.contains('show')) {
            userDrop.classList.remove('show');
            userBtn?.setAttribute('aria-expanded', 'false');
            userBtn?.focus();
        }
    });

    // ── Fullscreen ─────────────────────────────────────────────────────
    if (fullBtn) {
        fullBtn.addEventListener('click', function () {
            if (!document.fullscreenElement) {
                document.documentElement.requestFullscreen();
                fullBtn.querySelector('i').className = 'fas fa-compress';
            } else {
                document.exitFullscreen();
                fullBtn.querySelector('i').className = 'fas fa-expand';
            }
        });
    }

    // Borrador del wizard «Nuevo envío»: no debe sobrevivir al cerrar sesión
    document.querySelectorAll('a[href*="logout"]').forEach(function (link) {
        link.addEventListener('click', function (e) {
            e.preventDefault();
            const destino = link.getAttribute('href');
            if (!destino) return;
            try { sessionStorage.removeItem('agrofusion_envio_borrador_v1'); } catch (err) {}
            if (window.SimulacionRuta && typeof window.SimulacionRuta.marcarLogout === 'function') {
                window.SimulacionRuta.marcarLogout();
            } else {
                window.__agrofusionLoggingOut = true;
            }
            if (window.SimulacionMapaGlobal && typeof window.SimulacionMapaGlobal.destruir === 'function') {
                window.SimulacionMapaGlobal.destruir();
            }
            window.location.replace(destino);
        });
    });

})();
</script>
