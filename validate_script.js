const fs = require('fs');
const html = fs.readFileSync('c:/Users/Alex/Documents/GitHub/project-SF/templates/dashboard.html', 'utf8');

const regex = /<script.*?>([\s\S]*?)<\/script>/g;
let match;
while ((match = regex.exec(html)) !== null) {
    try {
        new Function(match[1]);
    } catch (e) {
        console.error('Syntax error in <script> tag:', e.message);
    }
}
