document.addEventListener('DOMContentLoaded', function() {
    // Add video background to the page
    const videoBackground = document.createElement('video');
    videoBackground.className = 'background-video';
    videoBackground.autoplay = true;
    videoBackground.loop = true;
    videoBackground.muted = true;
    videoBackground.playsinline = true;
    
    // Apply brightness filter to make the background brighter
    videoBackground.style.filter = 'brightness(0.3)';
    
    // Create source element
    const source = document.createElement('source');
    source.src = 'assets/background.mp4';
    source.type = 'video/mp4';
    
    // Append source to video and video to body
    videoBackground.appendChild(source);
    document.body.insertBefore(videoBackground, document.body.firstChild);
    
    // Add CSS for snap scrolling
    const style = document.createElement('style');
    style.textContent = `
        html {
            scroll-behavior: smooth;
            scroll-snap-type: y mandatory;
            overflow-y: scroll;
        }
        
        main, section {
            scroll-snap-align: start;
            scroll-snap-stop: always;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        
        footer {
            scroll-snap-align: start;
        }
        
        /* Ensure proper spacing for sections */
        #thesis, #what-we-do, #portfolio {
            padding-top: 80px; /* Adjust based on your header height */
            padding-bottom: 40px;
            box-sizing: border-box;
        }
        
        /* Additional style for the background video */
        .background-video {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            object-fit: cover;
            z-index: -1;
            filter: brightness(1.3); /* Make the video brighter */
        }
    `;
    document.head.appendChild(style);
    
    // Set up scroll handling
    const sections = ['thesis', 'what-we-do', 'portfolio'];
    let currentSectionIndex = 0;
    let isScrolling = false;
    
    // Prevent default scroll and handle with custom logic
    window.addEventListener('wheel', function(e) {
        if (isScrolling) return;
        
        isScrolling = true;
        
        if (e.deltaY > 0) {
            // Scrolling down
            currentSectionIndex = Math.min(currentSectionIndex + 1, sections.length - 1);
        } else {
            // Scrolling up
            currentSectionIndex = Math.max(currentSectionIndex - 1, 0);
        }
        
        // Scroll to the target section
        document.getElementById(sections[currentSectionIndex]).scrollIntoView({ behavior: 'smooth' });
        
        // Reset scrolling flag after animation completes
        setTimeout(() => {
            isScrolling = false;
        }, 2000);
        
        e.preventDefault();
    }, { passive: false });
    
    // Handle keyboard navigation
    document.addEventListener('keydown', function(e) {
        if (isScrolling) return;
        
        if (e.key === 'ArrowDown' || e.key === 'PageDown') {
            isScrolling = true;
            currentSectionIndex = Math.min(currentSectionIndex + 1, sections.length - 1);
            document.getElementById(sections[currentSectionIndex]).scrollIntoView({ behavior: 'smooth' });
            setTimeout(() => { isScrolling = false; }, 2000);
            e.preventDefault();
        } else if (e.key === 'ArrowUp' || e.key === 'PageUp') {
            isScrolling = true;
            currentSectionIndex = Math.max(currentSectionIndex - 1, 0);
            document.getElementById(sections[currentSectionIndex]).scrollIntoView({ behavior: 'smooth' });
            setTimeout(() => { isScrolling = false; }, 2000);
            e.preventDefault();
        }
    });
    
    // Also handle navigation clicks
    document.querySelectorAll('nav a').forEach(function(link, index) {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            currentSectionIndex = index;
            document.getElementById(sections[currentSectionIndex]).scrollIntoView({ behavior: 'smooth' });
        });
    });
    
    // Determine initial section based on scroll position
    function updateCurrentSection() {
        const scrollPosition = window.scrollY;
        
        for (let i = sections.length - 1; i >= 0; i--) {
            const section = document.getElementById(sections[i]);
            if (scrollPosition >= section.offsetTop - 100) {
                currentSectionIndex = i;
                break;
            }
        }
    }
    
    // Update section on page load
    updateCurrentSection();
    
    // Initialize AOS
    AOS.init({
        duration: 2000,
        offset: 150,
        easing: 'ease-in-out',
        mirror: true,
    });
});