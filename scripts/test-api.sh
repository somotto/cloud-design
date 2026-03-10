#!/bin/bash

API_URL="http://localhost:3000"

echo "=== Testing Orchestrator API ==="
echo ""

echo "1. Creating a movie..."
curl -X POST ${API_URL}/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title": "Inception", "description": "A mind-bending thriller by Christopher Nolan"}' \
  -s | jq .
echo ""

echo "2. Getting all movies..."
curl -s ${API_URL}/api/movies | jq .
echo ""

echo "3. Creating another movie..."
curl -X POST ${API_URL}/api/movies \
  -H "Content-Type: application/json" \
  -d '{"title": "The Matrix", "description": "A computer hacker learns about the true nature of reality"}' \
  -s | jq .
echo ""

echo "4. Getting all movies again..."
curl -s ${API_URL}/api/movies | jq .
echo ""

echo "5. Sending order to billing queue..."
curl -X POST ${API_URL}/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{"user_id": 123, "number_of_items": 2, "total_amount": 29.99}' \
  -s | jq .
echo ""

echo "6. Sending another order..."
curl -X POST ${API_URL}/api/billing/ \
  -H "Content-Type: application/json" \
  -d '{"user_id": 456, "number_of_items": 1, "total_amount": 14.99}' \
  -s | jq .
echo ""

echo "=== Test Complete ==="
echo "Check billing-app logs to verify order processing:"
echo "kubectl logs -n orchestrator -l app=billing-app --tail=20"
