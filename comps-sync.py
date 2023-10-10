#!/usr/bin/python3

# basic-desktop-environment
# cloud-server-environment
# custom-environment
# developer-workstation-environment
# infrastructure-server-environment
# minimal-environment
# server-product-environment
# web-server-environment
# workstation-product-environment

import argparse, yaml
import libcomps

# function to write comps group to yaml file
def output_group(group, packages, dest):

    with open(f'{dest}/{group}.yaml', 'w') as f:
        # write group header
        f.write("# {} group\n".format(group))
        f.write("packages:\n")

        for type in ['mandatory', 'default']:
            if len(packages[type]) > 0:
                f.write("  # {} packages\n".format(type))
                for package in sorted(packages[type]):
                    f.write("  - {}\n".format(package))

        for type in ['conditional', 'optional']:
            if len(packages[type]) > 0:
                f.write("  # {} packages\n".format(type))
                for package in sorted(packages[type]):
                    f.write("  # - {}\n".format(package))

# argument parser
parser = argparse.ArgumentParser()
parser.add_argument("--dest", help="destination directory", default="comps-standard", required=False)
parser.add_argument("--source", help="source xml.in file", default="fedora-comps/comps-f39.xml.in", required=False)
parser.add_argument("--environment", help="dnf environment", default="workstation-product-environment", required=False)
args = parser.parse_args()

# # read in packages to exclude from comps
# with open('comps-custom-exclude.yaml') as f:
#     comps_exclude = yaml.safe_load(f)

# load standard fedora comps
comps = libcomps.Comps()
comps.fromxml_f(args.source)

filtered = comps.arch_filter(["x86_64"])
mandatory_groups = filtered.environments[args.environment].group_ids
optional_groups = filtered.environments[args.environment].option_ids

# set the environment
print(f"# {args.environment}")
print("include:")
print("  # mandatory groups")
for g in mandatory_groups:
    print(f"  - {args.dest}/{g.name}.yaml")
print("  # optional groups")
for g in optional_groups:
    print(f"  # - {args.dest}/{g.name}.yaml")

# iterate through groups pulling out mandatory and default packages
group_packages = {}
for group_id in list(mandatory_groups) + list(optional_groups):
    group_packages[group_id.name] = {
        "mandatory": [],
        "default": [],
        "conditional": [],
        "optional": [],
    }

    group = filtered.groups_match(id=group_id.name)[0]
    # group_exclude = comps_exclude.get(group_id.name, set())

    for package in group.packages:
        # if package.name not in group_exclude:
        if package.type == libcomps.PACKAGE_TYPE_MANDATORY:
            group_packages[group_id.name]["mandatory"].append(package.name)
        elif package.type == libcomps.PACKAGE_TYPE_DEFAULT:
            group_packages[group_id.name]["default"].append(package.name)
        elif package.type == libcomps.PACKAGE_TYPE_CONDITIONAL:
            group_packages[group_id.name]["conditional"].append(package.name)
        elif package.type == libcomps.PACKAGE_TYPE_OPTIONAL:
            group_packages[group_id.name]["optional"].append(package.name)
        else:
            continue

    output_group(group_id.name, group_packages[group_id.name], args.dest)
