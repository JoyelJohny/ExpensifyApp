import React, {useState} from 'react';
import type {ValueOf} from 'type-fest';
import FullPageNotFoundView from '@components/BlockingViews/FullPageNotFoundView';
import HeaderWithBackButton from '@components/HeaderWithBackButton';
import ScreenWrapper from '@components/ScreenWrapper';
import SelectionList from '@components/SelectionList';
import RadioListItem from '@components/SelectionList/RadioListItem';
import useLocalize from '@hooks/useLocalize';
import Navigation from '@libs/Navigation/Navigation';
import * as PolicyUtils from '@libs/PolicyUtils';
import withPolicy from '@pages/workspace/withPolicy';
import type {WithPolicyOnyxProps} from '@pages/workspace/withPolicy';
import * as Policy from '@userActions/Policy';
import CONST from '@src/CONST';
import {isEmptyObject} from '@src/types/utils/EmptyObject';

const DAYS_OF_MONTH = 28;

type WorkspaceAutoReportingMonthlyOffsetProps = WithPolicyOnyxProps;

type AutoReportingOffsetKeys = ValueOf<typeof CONST.POLICY.AUTO_REPORTING_OFFSET>;

type WorkspaceAutoReportingMonthlyOffsetPageItem = {
    text: string;
    keyForList: string;
    isSelected: boolean;
    isNumber?: boolean;
};

function WorkspaceAutoReportingMonthlyOffsetPage({policy}: WorkspaceAutoReportingMonthlyOffsetProps) {
    const {translate} = useLocalize();
    const offset = policy?.autoReportingOffset ?? 0;
    const [searchText, setSearchText] = useState('');
    const trimmedText = searchText.trim().toLowerCase();

    const daysOfMonth: WorkspaceAutoReportingMonthlyOffsetPageItem[] = Array.from({length: DAYS_OF_MONTH}, (value, index) => {
        const day = index + 1;
        let suffix = 'th';
        if (day === 1 || day === 21) {
            suffix = 'st';
        } else if (day === 2 || day === 22) {
            suffix = 'nd';
        } else if (day === 3 || day === 23) {
            suffix = 'rd';
        }

        return {
            text: `${day}${suffix}`,
            keyForList: day.toString(), // we have to cast it as string for <ListItem> to work
            isSelected: day === offset,
            isNumber: true,
        };
    }).concat([
        {
            keyForList: 'lastDayOfMonth',
            text: translate('workflowsPage.frequencies.lastDayOfMonth'),
            isSelected: offset === CONST.POLICY.AUTO_REPORTING_OFFSET.LAST_DAY_OF_MONTH,
            isNumber: false,
        },
        {
            keyForList: 'lastBusinessDayOfMonth',
            text: translate('workflowsPage.frequencies.lastBusinessDayOfMonth'),
            isSelected: offset === CONST.POLICY.AUTO_REPORTING_OFFSET.LAST_BUSINESS_DAY_OF_MONTH,
            isNumber: false,
        },
    ]);

    const filteredDaysOfMonth = daysOfMonth.filter((dayItem) => dayItem.text.toLowerCase().includes(trimmedText));

    const headerMessage = searchText.trim() && !filteredDaysOfMonth.length ? translate('common.noResultsFound') : '';

    const onSelectDayOfMonth = (item: WorkspaceAutoReportingMonthlyOffsetPageItem) => {
        Policy.setWorkspaceAutoReportingMonthlyOffset(policy?.id ?? '', item.isNumber ? parseInt(item.keyForList, 10) : (item.keyForList as AutoReportingOffsetKeys));
        Navigation.goBack();
    };

    return (
        <ScreenWrapper
            includeSafeAreaPaddingBottom={false}
            testID={WorkspaceAutoReportingMonthlyOffsetPage.displayName}
        >
            <FullPageNotFoundView
                onBackButtonPress={PolicyUtils.goBackFromInvalidPolicy}
                onLinkPress={PolicyUtils.goBackFromInvalidPolicy}
                shouldShow={isEmptyObject(policy) || !PolicyUtils.isPolicyAdmin(policy) || PolicyUtils.isPendingDeletePolicy(policy) || !PolicyUtils.isPaidGroupPolicy(policy)}
                subtitleKey={isEmptyObject(policy) ? undefined : 'workspace.common.notAuthorized'}
            >
                <HeaderWithBackButton
                    title={translate('workflowsPage.submissionFrequency')}
                    onBackButtonPress={Navigation.goBack}
                />

                <SelectionList
                    sections={[{data: filteredDaysOfMonth, indexOffset: 0}]}
                    textInputLabel={translate('workflowsPage.submissionFrequencyDayOfMonth')}
                    textInputValue={searchText}
                    onChangeText={setSearchText}
                    headerMessage={headerMessage}
                    ListItem={RadioListItem}
                    onSelectRow={onSelectDayOfMonth}
                    initiallyFocusedOptionKey={offset.toString()}
                    showScrollIndicator
                />
            </FullPageNotFoundView>
        </ScreenWrapper>
    );
}

WorkspaceAutoReportingMonthlyOffsetPage.displayName = 'WorkspaceAutoReportingMonthlyOffsetPage';
export default withPolicy(WorkspaceAutoReportingMonthlyOffsetPage);
