//
//  WeChatiOS_captain.mm
//  WeChatiOS_captain
//
//  Created by honeyeeb on 2018/1/28.
//  Copyright (c) 2018年 ___ORGANIZATIONNAME___. All rights reserved.
//

// CaptainHook by Ryan Petrich
// see https://github.com/rpetrich/CaptainHook/

#if TARGET_OS_SIMULATOR
#error Do not support the simulator, please use the real iPhone Device.
#endif

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CaptainHook/CaptainHook.h"
#include <notify.h> // not required; for examples only
#import "WeChatRobot.h"
#import "TKSettingViewController.h"
#import "EmoticonGameCheat.h"
#import "FLEXManager.h"

// Objective-C runtime hooking using CaptainHook:
//   1. declare class using CHDeclareClass()
//   2. load class using CHLoadClass() or CHLoadLateClass() in CHConstructor
//   3. hook method using CHOptimizedMethod()
//   4. register hook using CHHook() in CHConstructor
//   5. (optionally) call old method using CHSuper()

@interface WeChatiOS_captain : NSObject

@end

@implementation WeChatiOS_captain

- (id)init {
    if ((self = [super init])) {
        
    }
    return self;
}

+ (void)load {
    [super load];
    
}

@end


#pragma mark - Message
CHDeclareClass(CMessageMgr)
CHOptimizedMethod(2, self, void, CMessageMgr, AddEmoticonMsg, NSString *, msg, msgWrap, CMessageWrap *, msgWrap) {
    if ([[TKRobotConfig sharedConfig] preventGameCheatEnable]) {
        // 是否开启游戏作弊
        if ([msgWrap m_uiMessageType] == 47 && ([msgWrap m_uiGameType] == 2|| [msgWrap m_uiGameType] == 1)) {
            [EmoticonGameCheat showEoticonCheat:[msgWrap m_uiGameType] callback:^(NSInteger random){
                [msgWrap setM_nsEmoticonMD5:[objc_getClass("GameController") getMD5ByGameContent:random]];
                [msgWrap setM_uiGameContent:random];
                CHSuper2(CMessageMgr, AddEmoticonMsg, msg, msgWrap, msgWrap);
            }];
            return;
        }
    }
    CHSuper2(CMessageMgr, AddEmoticonMsg, msg, msgWrap, msgWrap);
}

CHOptimizedMethod(3, self, void, CMessageMgr, MessageReturn, unsigned int, arg1, MessageInfo, id, info, Event, unsigned int, arg3) {
    CHSuper3(CMessageMgr, MessageReturn, arg1, MessageInfo, info, Event, arg3);
    CMessageWrap *wrap = [info objectForKey:@"18"];

    if (arg1 == 227) {
        NSDate *now = [NSDate date];
        NSTimeInterval nowSecond = now.timeIntervalSince1970;
        if (nowSecond - wrap.m_uiCreateTime > 60) {      // 若是1分钟前的消息，则不进行处理。
            return;
        }
        CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
        CContact *contact = [contactMgr getContactByName:wrap.m_nsFromUsr];
        if(wrap.m_uiMessageType == 1) {                                         // 收到文本消息
            if (contact.m_uiFriendScene == 0 && ![contact isChatroom]) {
                //        该消息为公众号
                return;
            }
            if (![contact isChatroom]) {                                        // 是否为群聊
                [self autoReplyWithMessageWrap:wrap];                           // 自动回复个人消息
            } else {
                [self removeMemberWithMessageWrap:wrap];                        // 自动踢人
                [self autoReplyChatRoomWithMessageWrap:wrap];                   // 自动回复群消息
            }
        } else if(wrap.m_uiMessageType == 10000) {                              // 收到群通知，eg:群邀请了好友；删除了好友。
            CContact *selfContact = [contactMgr getSelfContact];
            if([selfContact.m_nsUsrName isEqualToString:contact.m_nsOwner]) {   // 只有自己创建的群，才发送群欢迎语
                [self welcomeJoinChatRoomWithMessageWrap:wrap];
            }
        }
    } else if (arg1 == 332) {                                                          // 收到添加好友消息
        [self addAutoVerifyWithMessageInfo:info];
    }
}

CHOptimizedMethod(3, self, id, CMessageMgr, GetHelloUsers, id, arg1, Limit, unsigned int, arg2, OnlyUnread, BOOL, arg3) {
    id userNameArray = CHSuper3(CMessageMgr, GetHelloUsers, arg1, Limit, arg2, OnlyUnread, arg3);
    if ([arg1 isEqualToString:@"fmessage"] && arg2 == 0 && arg3 == 0) {
        [self addAutoVerifyWithArray:userNameArray arrayType:TKArrayTpyeMsgUserName];
    }
    return userNameArray;
}

CHOptimizedMethod(1, self, void, CMessageMgr, onRevokeMsg, CMessageWrap *, arg1) {
    if ([[TKRobotConfig sharedConfig] preventRevokeEnable]) {
        NSString *msgContent = arg1.m_nsContent;

        NSString *(^parseParam)(NSString *, NSString *,NSString *) = ^NSString *(NSString *content, NSString *paramBegin,NSString *paramEnd) {
            NSUInteger startIndex = [content rangeOfString:paramBegin].location + paramBegin.length;
            NSUInteger endIndex = [content rangeOfString:paramEnd].location;
            NSRange range = NSMakeRange(startIndex, endIndex - startIndex);
            return [content substringWithRange:range];
        };

        NSString *session = parseParam(msgContent, @"<session>", @"</session>");
        NSString *newmsgid = parseParam(msgContent, @"<newmsgid>", @"</newmsgid>");
        NSString *fromUsrName = parseParam(msgContent, @"<![CDATA[", @"撤回了一条消息");
        CMessageWrap *revokemsg = [self GetMsg:session n64SvrID:[newmsgid integerValue]];

        CContactMgr *contactMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CContactMgr")];
        CContact *selfContact = [contactMgr getSelfContact];
        NSString *newMsgContent = @"";


        if ([revokemsg.m_nsFromUsr isEqualToString:selfContact.m_nsUsrName]) {
            if (revokemsg.m_uiMessageType == 1) {       // 判断是否为文本消息
                newMsgContent = [NSString stringWithFormat:@"拦截到你撤回了一条消息：\n %@",revokemsg.m_nsContent];
            } else {
                newMsgContent = @"拦截到你撤回一条消息";
            }
        } else {
            if (revokemsg.m_uiMessageType == 1) {
                newMsgContent = [NSString stringWithFormat:@"拦截到一条 %@撤回消息：\n %@",fromUsrName, revokemsg.m_nsContent];
            } else {
                newMsgContent = [NSString stringWithFormat:@"拦截到一条 %@撤回消息",fromUsrName];
            }
        }

        CMessageWrap *newWrap = ({
            CMessageWrap *msg = [[NSClassFromString(@"CMessageWrap") alloc] initWithMsgType:0x2710];
            [msg setM_nsFromUsr:revokemsg.m_nsFromUsr];
            [msg setM_nsToUsr:revokemsg.m_nsToUsr];
            [msg setM_uiStatus:0x4];
            [msg setM_nsContent:newMsgContent];
            [msg setM_uiCreateTime:[arg1 m_uiCreateTime]];

            msg;
        });

        [self AddLocalMsg:session MsgWrap:newWrap fixTime:0x1 NewMsgArriveNotify:0x0];
        return;
    }
    CHSuper1(CMessageMgr, onRevokeMsg, arg1);
}

CHDeclareMethod(1 ,void, CMessageMgr, autoReplyWithMessageWrap, CMessageWrap *, wrap) {
    BOOL autoReplyEnable = [[TKRobotConfig sharedConfig] autoReplyEnable];
    NSString *autoReplyContent = [[TKRobotConfig sharedConfig] autoReplyText];
    if (!autoReplyEnable || autoReplyContent == nil || [autoReplyContent isEqualToString:@""]) {                                                     // 是否开启自动回复
        return;
    }

    NSString * content = [wrap valueForKey:@"m_nsLastDisplayContent"];
    NSString *needAutoReplyMsg = [[TKRobotConfig sharedConfig] autoReplyKeyword];
    NSArray * keyWordArray = [needAutoReplyMsg componentsSeparatedByString:@"||"];
    [keyWordArray enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([keyword isEqualToString:@"*"] || [content isEqualToString:keyword]) {
            [self sendMsg:autoReplyContent toContactUsrName:wrap.m_nsFromUsr];
        }
    }];
}
CHDeclareMethod(1, void, CMessageMgr, removeMemberWithMessageWrap, CMessageWrap *, wrap) {
    BOOL chatRoomSensitiveEnable = [[TKRobotConfig sharedConfig] chatRoomSensitiveEnable];
    if (!chatRoomSensitiveEnable) {
        return;
    }

    CGroupMgr *groupMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:objc_getClass("CGroupMgr")];
    NSString *content = [wrap valueForKey:@"m_nsLastDisplayContent"];
    NSMutableArray *array = [[TKRobotConfig sharedConfig] chatRoomSensitiveArray];
    [array enumerateObjectsUsingBlock:^(NSString *text, NSUInteger idx, BOOL * _Nonnull stop) {
        if([content isEqualToString:text]) {
            [groupMgr DeleteGroupMember:wrap.m_nsFromUsr withMemberList:@[wrap.m_nsRealChatUsr] scene:3074516140857229312];
        }
    }];
}
CHDeclareMethod(1, void, CMessageMgr, autoReplyChatRoomWithMessageWrap, CMessageWrap *, wrap) {
    BOOL autoReplyChatRoomEnable = [[TKRobotConfig sharedConfig] autoReplyChatRoomEnable];
    NSString *autoReplyChatRoomContent = [[TKRobotConfig sharedConfig] autoReplyChatRoomText];
    if (!autoReplyChatRoomEnable || autoReplyChatRoomContent == nil || [autoReplyChatRoomContent isEqualToString:@""]) {                                                     // 是否开启自动回复
        return;
    }

    NSString * content = [wrap valueForKey:@"m_nsLastDisplayContent"];
    NSString *needAutoReplyChatRoomMsg = [[TKRobotConfig sharedConfig] autoReplyChatRoomKeyword];
    NSArray * keyWordArray = [needAutoReplyChatRoomMsg componentsSeparatedByString:@"||"];
    [keyWordArray enumerateObjectsUsingBlock:^(NSString *keyword, NSUInteger idx, BOOL * _Nonnull stop) {
        if ([keyword isEqualToString:@"*"] || [content isEqualToString:keyword]) {
            [self sendMsg:autoReplyChatRoomContent toContactUsrName:wrap.m_nsFromUsr];
        }
    }];
}
CHDeclareMethod(1, void, CMessageMgr, welcomeJoinChatRoomWithMessageWrap, CMessageWrap *, wrap) {
    BOOL welcomeJoinChatRoomEnable = [[TKRobotConfig sharedConfig] welcomeJoinChatRoomEnable];
    if (!welcomeJoinChatRoomEnable) return;                                     // 是否开启入群欢迎语
    NSString * content = [wrap valueForKey:@"m_nsLastDisplayContent"];
    NSRange rangeFrom = [content rangeOfString:@"邀请\""];
    NSRange rangeTo = [content rangeOfString:@"\"加入了群聊"];
    NSRange nameRange;
    if (rangeFrom.length > 0 && rangeTo.length > 0) {                           // 通过别人邀请进群
        NSInteger nameLocation = rangeFrom.location + rangeFrom.length;
        nameRange = NSMakeRange(nameLocation, rangeTo.location - nameLocation);
    } else {
        NSRange range = [content rangeOfString:@"\"通过扫描\""];
        if (range.length > 0) {                                                 // 通过二维码扫描进群
            nameRange = NSMakeRange(2, range.location - 2);
        } else {
            return;
        }
    }
    NSString *welcomeJoinChatRoomText = [[TKRobotConfig sharedConfig] welcomeJoinChatRoomText];
    [self sendMsg:welcomeJoinChatRoomText toContactUsrName:wrap.m_nsFromUsr];
}
CHDeclareMethod(1, void, CMessageMgr, addAutoVerifyWithMessageInfo, NSDictionary *, info) {
    BOOL autoVerifyEnable = [[TKRobotConfig sharedConfig] autoVerifyEnable];

    if (!autoVerifyEnable)
        return;

    NSString *keyStr = [info objectForKey:@"5"];
    if ([keyStr isEqualToString:@"fmessage"]) {
        NSArray *wrapArray = [info objectForKey:@"27"];
        [self addAutoVerifyWithArray:wrapArray arrayType:TKArrayTpyeMsgWrap];
    }
}
CHDeclareMethod(2, void, CMessageMgr, addAutoVerifyWithArray, NSArray *, ary, arrayType, TKArrayTpye, type) {
    NSMutableArray *arrHellos = [NSMutableArray array];
    [ary enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (type == TKArrayTpyeMsgWrap) {
            CPushContact *contact = [objc_getClass("SayHelloDataLogic") getContactFrom:obj];
            [arrHellos addObject:contact];
        } else if (type == TKArrayTpyeMsgUserName) {
            FriendAsistSessionMgr *asistSessionMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:NSClassFromString(@"FriendAsistSessionMgr")];
            CMessageWrap *wrap = [asistSessionMgr GetLastMessage:@"fmessage" HelloUser:obj OnlyTo:NO];
            CPushContact *contact = [objc_getClass("SayHelloDataLogic") getContactFrom:wrap];
            [arrHellos addObject:contact];
        }
    }];

    NSString *autoVerifyKeyword = [[TKRobotConfig sharedConfig] autoVerifyKeyword];
    for (int idx = 0;idx < arrHellos.count;idx++) {
        CPushContact *contact = arrHellos[idx];
        if (![contact isMyContact] && [contact.m_nsDes isEqualToString:autoVerifyKeyword]) {
            CContactVerifyLogic *verifyLogic = [[objc_getClass("CContactVerifyLogic") alloc] init];
            CVerifyContactWrap *wrap = [[objc_getClass("CVerifyContactWrap") alloc] init];
            [wrap setM_nsUsrName:contact.m_nsEncodeUserName];
            [wrap setM_uiScene:contact.m_uiFriendScene];
            [wrap setM_nsTicket:contact.m_nsTicket];
            [wrap setM_nsChatRoomUserName:contact.m_nsChatRoomUserName];
            wrap.m_oVerifyContact = contact;

            AutoSetRemarkMgr *mgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:NSClassFromString(@"AutoSetRemarkMgr")];
            id attr = [mgr GetStrangerAttribute:contact AttributeName:1001];

            if([attr boolValue]) {
                [wrap setM_uiWCFlag:(wrap.m_uiWCFlag | 1)];
            }
            [verifyLogic startWithVerifyContactWrap:[NSArray arrayWithObject:wrap] opCode:3 parentView:[UIView new] fromChatRoom:NO];

            // 发送欢迎语
            BOOL autoWelcomeEnable = [[TKRobotConfig sharedConfig] autoWelcomeEnable];
            NSString *autoWelcomeText = [[TKRobotConfig sharedConfig] autoWelcomeText];
            if (autoWelcomeEnable && autoWelcomeText != nil) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self sendMsg:autoWelcomeText toContactUsrName:contact.m_nsUsrName];
                });
            }
        }
    }
}

CHDeclareMethod(2, void, CMessageMgr, sendMsg, NSString *, msg, toContactUsrName, NSString *, userName) {
    CMessageWrap *wrap = [[objc_getClass("CMessageWrap") alloc] initWithMsgType:1];
    id usrName = [objc_getClass("SettingUtil") getLocalUsrName:0];
    [wrap setM_nsFromUsr:usrName];
    [wrap setM_nsContent:msg];
    [wrap setM_nsToUsr:userName];
    MMNewSessionMgr *sessionMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:NSClassFromString(@"MMNewSessionMgr")];
    [wrap setM_uiCreateTime:[sessionMgr GenSendMsgTime]];
    [wrap setM_uiStatus:YES];

    CMessageMgr *chatMgr = [[objc_getClass("MMServiceCenter") defaultCenter] getService:NSClassFromString(@"CMessageMgr")];
    [chatMgr AddMsg:userName MsgWrap:wrap];
}

#pragma amrk - 设置小助手
CHDeclareClass(NewSettingViewController)
CHOptimizedMethod(0, self, void, NewSettingViewController, reloadTableData) {
    CHSuper0(NewSettingViewController, reloadTableData);
    MMTableViewInfo *tableViewInfo = [self valueForKey:@"m_tableViewInfo"];
    MMTableViewSectionInfo *sectionInfo = [objc_getClass("MMTableViewSectionInfo") sectionInfoDefaut];
    MMTableViewCellInfo *settingCell = [objc_getClass("MMTableViewCellInfo") normalCellForSel:@selector(assistenceSetting) target:self title:@"微信小助手" accessoryType:1];
    [sectionInfo addCell:settingCell];
    MMTableViewCellInfo *flexCell = [NSClassFromString(@"MMTableViewCellInfo") normalCellForSel:@selector(enableFlex) target:self title:@"FLEX" accessoryType:1];
    [sectionInfo addCell:flexCell];
    [tableViewInfo insertSection:sectionInfo At:0];
    MMTableView *tableView = [tableViewInfo getTableView];
    [tableView reloadData];
    
}
CHDeclareMethod(0, void, NewSettingViewController, assistenceSetting) {
    TKSettingViewController *settingViewController = [[objc_getClass("TKSettingViewController") alloc] init];
    [self.navigationController PushViewController:settingViewController animated:YES];
}

CHDeclareMethod(0, void, NewSettingViewController, enableFlex) {

    [[objc_getClass("FLEXManager") sharedManager] showExplorer];
}

CHDeclareClass(WCDeviceStepObject)
CHOptimizedMethod(0, self, NSInteger, WCDeviceStepObject, m7StepCount) {
    NSInteger stepCount = CHSuper0(WCDeviceStepObject, m7StepCount);
    NSInteger newStepCount = [[TKRobotConfig sharedConfig] deviceStep];
    BOOL changeStepEnable = [[TKRobotConfig sharedConfig] changeStepEnable];
    
    return changeStepEnable ? newStepCount : stepCount;
}
CHOptimizedMethod(0, self, NSInteger, WCDeviceStepObject, hkStepCount) {
    NSInteger stepCount = CHSuper0(WCDeviceStepObject, hkStepCount);
    NSInteger newStepCount = [[TKRobotConfig sharedConfig] deviceStep];
    BOOL changeStepEnable = [[TKRobotConfig sharedConfig] changeStepEnable];
    
    return changeStepEnable ? newStepCount : stepCount;
}

static void WillEnterForeground(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	// not required; for example only
}

static void ExternallyPostedNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)
{
	// not required; for example only
}

CHConstructor // code block that runs immediately upon load
{
	@autoreleasepool
	{
		// listen for local notification (not required; for example only)
		CFNotificationCenterRef center = CFNotificationCenterGetLocalCenter();
		CFNotificationCenterAddObserver(center, NULL, WillEnterForeground, CFSTR("UIApplicationWillEnterForegroundNotification"), NULL, CFNotificationSuspensionBehaviorCoalesce);
		
		// listen for system-side notification (not required; for example only)
		// this would be posted using: notify_post("com.honey.WeChatiOS-captain.eventname");
		CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
		CFNotificationCenterAddObserver(darwin, NULL, ExternallyPostedNotification, CFSTR("com.honey.WeChatiOS-captain.eventname"), NULL, CFNotificationSuspensionBehaviorCoalesce);
		
		// CHLoadClass(ClassToHook); // load class (that is "available now")
		// CHLoadLateClass(ClassToHook);  // load class (that will be "available later")
        
        CHLoadLateClass(CMessageMgr);
        CHHook2(CMessageMgr, AddEmoticonMsg, msgWrap);
        CHHook3(CMessageMgr, MessageReturn, MessageInfo, Event);
        CHHook3(CMessageMgr, GetHelloUsers, Limit, OnlyUnread);
        CHHook1(CMessageMgr, onRevokeMsg);
        CHHook1(CMessageMgr, autoReplyWithMessageWrap);
        CHHook1(CMessageMgr, removeMemberWithMessageWrap);
        CHHook1(CMessageMgr, autoReplyChatRoomWithMessageWrap);
        CHHook1(CMessageMgr, welcomeJoinChatRoomWithMessageWrap);
        CHHook1(CMessageMgr, addAutoVerifyWithMessageInfo);
        CHHook2(CMessageMgr, addAutoVerifyWithArray, arrayType);
        CHHook2(CMessageMgr, sendMsg, toContactUsrName);
        
        CHLoadLateClass(NewSettingViewController);
        CHHook0(NewSettingViewController, reloadTableData);
        CHHook0(NewSettingViewController, assistenceSetting);
        CHHook0(NewSettingViewController, enableFlex);
        CHLoadLateClass(WCDeviceStepObject);
        CHHook0(WCDeviceStepObject, m7StepCount);
        CHHook0(WCDeviceStepObject, hkStepCount);
        
	}
}
