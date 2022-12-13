from __future__ import absolute_import, division, print_function

__metaclass__ = type


DOCUMENTATION = """
  options:
    pattern:
      type: string
      required: True
"""

import pathlib
import re

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.utils.display import Display

display = Display()


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        self.set_options(var_options=variables, direct=kwargs)

        pattern = re.compile(self.get_option("pattern"))

        results = {}
        for term in terms:
            unit_dir = self.find_file_in_search_path(variables, "files", term)
            if not unit_dir:
                raise AnsibleError("could not locate file in lookup: %s" % term)

            unit_dir = pathlib.Path(unit_dir)
            if not unit_dir.is_dir():
                raise AnsibleError(f"{unit_dir} is not a directory")

            for file in unit_dir.glob("*.container"):
                name = file.stem

                with file.open() as f:
                    for line in f.readlines():
                        m = pattern.match(line)
                        if m is None:
                            continue

                        item = m.group(1)

                        if name in results:
                            raise AnsibleError(
                                f"{name} has multiple items of the same value"
                            )

                        if item in results.values():
                            raise AnsibleError(
                                f"{item} does already exist in another unit"
                            )

                        results[name] = item

        return [sorted(results.items())]
