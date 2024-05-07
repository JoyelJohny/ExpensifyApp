import type {ReactNode} from 'react';
import React from 'react';
import {StyleProp, View, ViewStyle} from 'react-native';
import useThemeStyles from '@hooks/useThemeStyles';
import Badge from './Badge';
import Text from './Text';

type MoneyRequestHeaderStatusBarProps = {
    /** Title displayed in badge */
    title: string | ReactNode;

    /** Banner Description */
    description: string;

    /** Whether we show the border bottom */
    shouldShowBorderBottom: boolean;

    /** Whether we should use the danger theme color */
    danger?: boolean;

    /** Additional style for the banner */
    additionalViewStyle?: StyleProp<ViewStyle>;
};

function MoneyRequestHeaderStatusBar({title, description, shouldShowBorderBottom, danger = false, additionalViewStyle}: MoneyRequestHeaderStatusBarProps) {
    const styles = useThemeStyles();
    const borderBottomStyle = shouldShowBorderBottom ? styles.borderBottom : {};
    return (
        <View style={[styles.dFlex, styles.flexRow, styles.alignItemsCenter, styles.flexGrow1, styles.overflowHidden, styles.ph5, styles.pb3, borderBottomStyle]}>
            <View style={additionalViewStyle || [styles.mr3]}>
                {typeof title === 'string' ? (
                    <Badge
                        text={title}
                        badgeStyles={styles.ml0}
                        error={danger}
                    />
                ) : (
                    <View>{title}</View>
                )}
            </View>
            <View style={[styles.flexShrink1]}>
                <Text style={[styles.textLabelSupporting]}>{description}</Text>
            </View>
        </View>
    );
}

MoneyRequestHeaderStatusBar.displayName = 'MoneyRequestHeaderStatusBar';

export default MoneyRequestHeaderStatusBar;
