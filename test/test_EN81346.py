import logging
import os
from unittest import TestCase
from parameterized import parameterized

from EN81346.Identifier import EquipmentIdentifier

logging.basicConfig(level=os.environ.get('LOGLEVEL', 'INFO').upper())


def get_params():
    """Returns a list of parameters for each test case"""
    return [
        [
            '==FZ910=113++CAB+1CC01-X8.1:13',
            '==FZ910=113++CAB+1CC01-X8.1:13'
        ],
        [
            '==AbC910=113+1CC01.CAB-X9.1:13',
            '==AbC910=113+1CC01.CAB-X9.1:13'
        ],
        [
            '=FUNC+1MCC01.CAB-X9.1:13',
            '=FUNC+1MCC01.CAB-X9.1:13'
        ],
        [
            '=100+110-X1',
            '=100+110-X1'
        ],
        [
            '=100+110-X2',
            '=100+110-X2'
        ]
    ]


class TestEquipmentIdentifier(TestCase):

    @classmethod
    def setUpClass(cls) -> None:
        cls.__identifier = EquipmentIdentifier()

    @parameterized.expand(get_params())
    def test_identifier(self, request, response):
        self.__identifier.identifier = request
        self.assertEqual(response, self.__identifier.identifier)
