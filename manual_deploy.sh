#!/bin/bash
# manual_deploy.sh - Amplify manual deploy

set -e

echo "🚀 Building frontend..."
cd frontend

# Install dependencies
npm ci

# Build
npm run build

# Create deployment package
cd build
zip -r ../deploy.zip .
cd ..

echo "✅ Build complete!"
echo ""
echo "📦 Ez nagyon helytelen megkoyelitese a dolgoknak, DE package created: frontend/deploy.zip"
echo ""
echo "Next steps:"
echo "1. Go to AWS Amplify Console"
echo "2. Select your app: $(terraform output -raw amplify_app_id 2>/dev/null || echo 'robot-control-logs-dashboard')"
echo "3. Click 'Deploy without Git provider' or 'Manual deploy'"
echo "4. Upload: frontend/deploy.zip"
echo ""
echo "Or use AWS CLI:"
echo "aws amplify create-deployment --app-id \$(terraform output -raw amplify_app_id) --branch-name main --region eu-west-1"