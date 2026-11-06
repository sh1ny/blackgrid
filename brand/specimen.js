// Copies the dark room's markup into the light room so both always show the same components.
const dark = document.querySelector('.sp-room[data-theme="dark"]');
const light = document.getElementById('light-room');
light.innerHTML = dark.innerHTML.replace('>Dark<', '>Light<');
