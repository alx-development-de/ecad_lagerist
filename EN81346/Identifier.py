import logging
import re


class EquipmentIdentifier:

    def __init__(self):
        self._log = logging.getLogger('EN81346.' + self.__class__.__name__)
        self._log.debug(f'Initializing ne %s', self.__class__.__name__)

        self._complete_string = None
        self._segments = []

        self._structure_elements = {
            'location': '+',
            'function': '=',
            'product': '-'
        }

    @property
    def identifier(self) -> str:
        return self._complete_string

    @identifier.setter
    def identifier(self, identifier: str):
        old_identifier = self._complete_string
        self._complete_string = identifier
        self._log.debug(f'Equipment id string changed [%s]->[%s]',
                        old_identifier,
                        self.identifier)

        # Splitting the string into the segments
        reg_result = re.findall(r'[+=-]+[0-9a-zA-Z.]+', self._complete_string)
        if reg_result:
            self._log.debug(f'Identifier segments recognized: %s', ', '.join(reg_result))
