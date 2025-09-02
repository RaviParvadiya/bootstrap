#!/usr/bin/env bash
set -euo pipefail

# Update all bash shebangs from #!/bin/bash to #!/usr/bin/env bash

echo "Updating bash shebangs to use portable format..."

# Find all .sh files and update their shebangs
find . -name "*.sh" -type f -exec grep -l "^#!/bin/bash" {} \; | while read -r file; do
    echo "Updating: $file"
    sed -i '1s|^#!/bin/bash|#!/usr/bin/env bash|' "$file"
done

echo "Shebang update complete!"
echo "All scripts now use the portable #!/usr/bin/env bash format"