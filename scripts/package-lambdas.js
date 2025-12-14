const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const distDir = path.join(__dirname, '..', 'dist');
const lambdaDistDir = path.join(distDir, 'lambdas');

const lambdas = [
  'primary-lambda',
  'fallback-lambda',
  'degradation-lambda'
];

// Create lambda dist directory
if (!fs.existsSync(lambdaDistDir)) {
  fs.mkdirSync(lambdaDistDir, { recursive: true });
}

lambdas.forEach(lambda => {
  const lambdaDir = path.join(lambdaDistDir, lambda);
  const sourcePath = path.join(distDir, `${lambda}.js`);

  if (!fs.existsSync(sourcePath)) {
    console.warn(`Warning: ${sourcePath} not found, skipping ${lambda}`);
    return;
  }

  // Create lambda directory
  if (!fs.existsSync(lambdaDir)) {
    fs.mkdirSync(lambdaDir, { recursive: true });
  }

  // Copy compiled JS file as index.js (Lambda expects index.handler)
  fs.copyFileSync(sourcePath, path.join(lambdaDir, 'index.js'));

  // Copy source map if exists
  const mapPath = `${sourcePath}.map`;
  if (fs.existsSync(mapPath)) {
    fs.copyFileSync(mapPath, path.join(lambdaDir, 'index.js.map'));
  }

  // Create zip file
  const zipPath = path.join(lambdaDistDir, `${lambda}.zip`);
  try {
    execSync(`cd "${lambdaDir}" && zip -r "${zipPath}" .`, { stdio: 'pipe' });
    console.log(`Created: ${zipPath}`);
  } catch (error) {
    console.error(`Failed to create zip for ${lambda}:`, error.message);
  }
});

console.log('Lambda packaging complete!');
