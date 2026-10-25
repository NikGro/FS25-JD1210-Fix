#!/usr/bin/env python3
"""Applies the reviewed changes to the copied JD 1210G mod (text edits, original formatting kept)."""
import re
import sys

MOD = sys.argv[1]


def edit(path, pairs):
    p = f'{MOD}/{path}'
    s = open(p, encoding='utf-8-sig').read()
    for old, new, count in pairs:
        n = s.count(old)
        assert n == count, f'{path}: expected {count}x, found {n}x: {old[:80]!r}'
        s = s.replace(old, new)
    open(p, 'w', encoding='utf-8').write(s)
    return s


def regex(path, pattern, repl, count):
    p = f'{MOD}/{path}'
    s = open(p, encoding='utf-8').read()
    s2, n = re.subn(pattern, repl, s, flags=re.S)
    assert n == count, f'{path}: regex expected {count}, got {n}: {pattern[:60]}'
    open(p, 'w', encoding='utf-8').write(s2)


X = '1210G.xml'

# 1. transmission: real CVT instead of two gears that the automatic never changes
edit(X, [(
    '''<motor torqueScale="1.210" minRpm="850" maxRpm="2200" brakeForce="6.5" lowBrakeForceScale="0.5" dampingRateScale="1.6">''',
    '''<motor torqueScale="1.210" minRpm="850" maxRpm="2200" maxForwardSpeed="23" maxBackwardSpeed="23" brakeForce="6.5" lowBrakeForceScale="0.5" dampingRateScale="1.6">''', 1)])
regex(X, r'<transmission name="\$l10n_info_transmission_cvt">.*?</transmission>',
      '<transmission minForwardGearRatio="28" maxForwardGearRatio="300" minBackwardGearRatio="28" maxBackwardGearRatio="300" name="$l10n_info_transmission_cvt"/>', 1)

# 2. control group 2 is the load space, not a second "crane"
edit(X, [(
    '''<controlGroup name="$l10n_controlGroup_crane"/>
				<controlGroup name="$l10n_controlGroup_crane"/>''',
    '''<controlGroup name="$l10n_controlGroup_crane"/>
				<controlGroup name="$l10n_controlGroup_jdLoadSpace"/>''', 1)])

# 3. crane light fixed: no controls any more, stays in its start position
edit(X, [(
    '''<movingTool node="1>2|0|0|0|6">
                <controls groupIndex="2" axis="AXIS_CRANE_ARM3" invertAxis="false" mouseSpeedFactor="0.3" iconName="CRANE_ARM1_ROTATE_X" />
''', '''<movingTool node="1>2|0|0|0|6">
''', 1)])

# 4. interactive control removed completely (+ the animations only it used)
regex(X, r'\n\t<interactiveControl>.*?\n\t</interactiveControl>[ \t]*\n', '\n', 1)
for anim in ('laiptai', 'Durys', 'stoike1', 'stoike2', 'stoike3', 'Beacon', 'atramaside', 'atramaup', 'stoikesA'):
    regex(X, r'\n[ \t]*<animation name="%s"[^>]*>.*?</animation>[ \t]*' % anim, '', 1)
# beacon stays on the roof; the second copy in the door pocket goes
regex(X, r'\n[ \t]*<beaconLight node="0>0\|4\|0\|0\|0\|0\|0\|0\|0\|0\|0\|0\|1\|0\|0\|9\|0\|16"[^\n]*', '', 1)

# 5. duplicated hydraulic hose (second, identical entry)
s = open(f'{MOD}/{X}', encoding='utf-8').read()
blocks = list(re.finditer(r'\n[ \t]*<localHose>[ \t]*\n[ \t]*<hose type="hydraulicIn"  node="1>2\|0\|0\|0\|0\|0\|0\|2\|5".*?</localHose>', s, flags=re.S))
assert len(blocks) == 2 and blocks[0].group(0).strip() == blocks[1].group(0).strip()
s = s[:blocks[1].start()] + s[blocks[1].end():]
open(f'{MOD}/{X}', 'w', encoding='utf-8').write(s)

# 6. mouseSpeedFactor on <movingTool> is ignored by the game (belongs to <controls>)
edit(X, [(' mouseSpeedFactor="0.3">\n                <translation', '>\n                <translation', 7)])

# 7. symmetric wheel loads (right front boggie had front/back swapped)
edit(X, [
    ('restLoad="2.6" repr="frontRightBoggieFrontWheel"', 'restLoad="2.3" repr="frontRightBoggieFrontWheel"', 1),
    ('restLoad="2.3" repr="frontRightBoggieBackWheel"', 'restLoad="2.6" repr="frontRightBoggieBackWheel"', 1),
])

# 8. distinguishable tyre names in the shop
edit(X, [
    ('<wheelConfiguration name="forestKingF2" price="0" brand="NOKIAN" saveId="NOKIAN_DEFAULT">',
     '<wheelConfiguration name="Forest King F2 710/45" price="0" brand="NOKIAN" saveId="NOKIAN_DEFAULT">', 1),
    ('<wheelConfiguration name="forestKingF2" price="20000" brand="NOKIAN">',
     '<wheelConfiguration name="Forest King F2 800/40" price="20000" brand="NOKIAN">', 1),
])

# 9. own vehicle type with the easy arm control script
edit(X, [('<vehicle type="forwarder" ', '<vehicle type="jd1210gForwarder" ', 1)])
edit(X, [('        <name>JOHNDEERE 1210G</name>', '        <name>JOHNDEERE 1210G (NG)</name>', 1)])
# easy arm control parameters (read by scripts/JDEasyArmControl.lua)
edit(X, [('''    </cylindered>''', '''    </cylindered>

    <jdEasyArmControl slewNode="1>2|1" boomNode="1>2|1|0" jibNode="1>2|1|0|0" telescopeNode="1>2|1|0|0|0" telescope2Node="1>2|1|0|0|0|0" tipNode="componentJointGrapple" speed="1.3" invertY="false" invertZ="false"/>''', 1)])


# 10. cameras like the base game forwarders: outdoor, free indoor and the crane camera on the column;
#     the extra indoor camera that tracks the grapple goes (camera + its aiming moving part)
regex(X, r'\n[ \t]*<camera node="folowcamera"[^\n]*', '', 1)
regex(X, r'\n[ \t]*<movingPart node="0>0\|4\|0\|0\|0\|0\|0\|0\|0\|0\|0\|0\|1\|0\|0\|0\|2" referencePoint="camerafolowpoint"[^\n]*', '', 1)

# 11. no permanent hydraulic base load (the base game Rottne F20D has none either)
regex(X, r'\n[ \t]*<powerConsumer ptoRpm="350"[^\n]*', '', 1)

print('1210G.xml patched')

# ---------------------------------------------------------------- modDesc
M = 'modDesc.xml'
s = open(f'{MOD}/{M}', encoding='utf-8-sig').read()
# duplicated storeItems block at the end
second = s.rfind('<storeItems>')
assert s.count('<storeItems>') == 2
end = s.index('</storeItems>', second) + len('</storeItems>')
s = s[:second].rstrip() + '\n' + s[end:].lstrip('\t ')
# interactive control texts are no longer used
s = re.sub(r'\t\t<!-- Interactive Control -->.*?</text>\n(?=\n\t\t<text name="InteriorDeco">)', '', s, flags=re.S)
s = re.sub(r'\n\t\t<text name="actionIC_[^"]*">[^\n]*', '', s)
assert 'actionIC_' not in s, 'IC texts left'
s = s.replace('<version>1.0.0.1</version>', '<version>1.0.1.0</version>')
s = s.replace('<author>Rimvis</author>', '<author>Rimvis (NG edit: NikGro)</author>')
s = s.replace('<en>John Deere 1210G</en>', '<en>John Deere 1210G (NG)</en>\n        <de>John Deere 1210G (NG)</de>')
s = s.replace('<l10n>', '''<l10n>
		<text name="controlGroup_jdLoadSpace">	<en>Load space</en>	<de>Laderaum</de>	</text>''', 1)
s = s.replace('<multiplayer supported="true"/>', '''<multiplayer supported="true"/>

    <specializations>
        <specialization name="jdEasyArmControl" className="JDEasyArmControl" filename="scripts/JDEasyArmControl.lua"/>
    </specializations>

    <vehicleTypes>
        <type name="jd1210gForwarder" parent="forwarder" filename="$dataS/scripts/vehicles/Vehicle.lua">
            <specialization name="jdEasyArmControl"/>
        </type>
    </vehicleTypes>''', 1)
note = '''NG edit (private, not for redistribution):
- Real CVT transmission instead of two gears the automatic never changed.
- Easy crane control now works (own script, the crane model does not fit the base game system).
- Interactive control removed, beacon fixed on the roof, crane light fixed.
- Control group 2 is called "Load space". Small XML fixes (wheel loads, duplicate hose, tyre names, duplicate store item).

'''
s = s.replace('<en>\n<![CDATA[ This is', '<en>\n<![CDATA[' + note + 'This is', 1)
s = s.replace('<de>\n<![CDATA[Dies ist', '<de>\n<![CDATA[' + note.replace('NG edit (private, not for redistribution):', 'NG-Bearbeitung (privat, nicht zur Weitergabe):')
              .replace('Real CVT transmission instead of two gears the automatic never changed.', 'Echtes stufenloses Getriebe statt zwei Gängen, die die Automatik nie wechselte.')
              .replace('Easy crane control now works (own script, the crane model does not fit the base game system).', 'Einfache Kransteuerung funktioniert jetzt (eigenes Script, das Kranmodell passt nicht zum Basisspiel-System).')
              .replace('Interactive control removed, beacon fixed on the roof, crane light fixed.', 'Interactive Control entfernt, Rundumleuchte fest auf dem Dach, Kranlicht fest.')
              .replace('Control group 2 is called "Load space". Small XML fixes (wheel loads, duplicate hose, tyre names, duplicate store item).', 'Steuergruppe 2 heißt „Laderaum“. Kleine XML-Fixes (Radlasten, doppelter Schlauch, Reifennamen, doppelter Shop-Eintrag).')
              + 'Dies ist', 1)
assert 'NG edit' in s and 'NG-Bearbeitung' in s
open(f'{MOD}/{M}', 'w', encoding='utf-8').write(s)
print('modDesc.xml patched')
