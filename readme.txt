��� ����� ��������:
1. passfile.hide - ���� ������ ������ � ������ ��� ��������� ����� � �� rollback
������ �����: service;uer;hashpassword
������ ������ ������ ���� - service;uer;hashpassword
������ ��������� � ������� Hash.
��� ���� ����� �������� ��� ������ ���������
"P@ssword1" | ConvertTo-SecureString -AsPlainText -Force
����� ���������� hash ��������� � ���� passfile.hide

2. Hosts.csv.hide - ���� � ����������� �� ������
������ �����: group;host;mac
������ ������ ������ ���� - group;host;mac