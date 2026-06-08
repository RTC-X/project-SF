const fs = require('fs');
const html = fs.readFileSync('c:/Users/Alex/Documents/GitHub/project-SF/templates/dashboard.html', 'utf8');

const regex = /x-data="([^"]*)"/g;
let match;
while ((match = regex.exec(html)) !== null) {
    try {
        new Function('return ' + match[1]);
    } catch (e) {
        console.error('Syntax error in x-data:', e.message);
        console.error('Code snippet:', match[1].substring(0, 100) + '...');
    }
}

const clickRegex = /@click="([^"]*)"/g;
while ((match = clickRegex.exec(html)) !== null) {
    try {
        new Function(match[1]);
    } catch (e) {
        console.error('Syntax error in @click:', e.message);
        console.error('Code snippet:', match[1].substring(0, 100) + '...');
    }
}

console.log("Validation complete.");
