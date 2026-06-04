import re

mapping = {
    'FarmEnabled': 'farm_enabled',
    'SnipeEnabled': 'snipe_enabled',
    'ActivatePanel': 'activate_panel',
    'FarmAreas': 'active_areas',
    'TargetSets': 'target_enchant_sets',
    'WhitelistedSwords': 'whitelisted_uuids',
    'TargetPriority': 'target_priority',
    'AscenderEnabled': 'ascender_enabled',
    'AutoAscenderEnabled': 'ascender_enabled',
    'AscenderQueue': 'ascender_queue',
    'AscenderCriteria': 'ascender_criteria',
    'WebhookURL': 'webhook_url',
    'WebhookEnabled': 'webhook_enabled',
    'ActiveTargetSets': 'target_enchant_sets',
    'C2_PanelActive': 'activate_panel'
}

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We replace instances of the old terms with the new ones.
    # To avoid matching parts of words, we can use regex \b boundary
    new_content = content
    for old, new in mapping.items():
        new_content = re.sub(rf'\b{old}\b', new, new_content)
        
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {filepath}")
    else:
        print(f"No changes in {filepath}")

replace_in_file(r'c:\Users\Alex\Documents\GitHub\project-SF\premium_scripts\autofarm_with_c2.lua')
replace_in_file(r'c:\Users\Alex\Documents\GitHub\project-SF\templates\dashboard.html')
