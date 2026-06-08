const fs = require('fs');
const html = fs.readFileSync('c:/Users/Alex/Documents/GitHub/project-SF/templates/dashboard.html', 'utf8');

const regex = /(?:x-[a-z\-]+|@[a-z\-]+|:[a-zA-Z\-]+)="([^"]+)"/g;
let match;
while ((match = regex.exec(html)) !== null) {
    let expr = match[1];
    // ignore very simple ones
    if (expr === 'true' || expr === 'false' || expr === '' || !expr.includes(' ')) continue;
    
    // some x-transition classes aren't JS
    if (match[0].startsWith('x-transition')) continue;
    
    try {
        new Function('return ' + expr);
    } catch (e) {
        try {
            new Function(expr);
        } catch (e2) {
            console.error('Syntax error in expression:', match[0].substring(0, 50));
            console.error('Expression:', expr);
            console.error('Error:', e2.message);
        }
    }
}
console.log("Deep validation complete.");
