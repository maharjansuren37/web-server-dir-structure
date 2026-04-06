// Simple portfolio JavaScript
console.log('Portfolio site loaded');

// Add any interactive features here
document.addEventListener('DOMContentLoaded', function() {
    // Example: highlight current nav link based on page
    const currentPage = window.location.pathname.split('/').pop() || 'index.html';
    const navLinks = document.querySelectorAll('nav a');
    navLinks.forEach(link => {
        const href = link.getAttribute('href');
        if (href === currentPage) {
            link.style.fontWeight = 'bold';
        }
    });
});
