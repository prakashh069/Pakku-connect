import re

with open('lib/features/contacts/screens/contacts_tab.dart', 'r') as f:
    content = f.read()

# Replace _buildSearchBar with a dummy to remove it from slivers
content = re.sub(
    r'Widget _buildSearchBar\(CustomColors colors\) \{.*?\n  \}',
    '',
    content,
    flags=re.DOTALL
)

# Fix slivers list
content = content.replace(
    'SliverToBoxAdapter(child: _buildSearchBar(colors)),',
    'SliverToBoxAdapter(child: const SizedBox(height: 80)), // Space for floating pill'
)

with open('lib/features/contacts/screens/contacts_tab.dart', 'w') as f:
    f.write(content)
