/*
 RMModelEditor.m
 RuleModeler

 Created by King Chung Huang on 1/29/04.


 Copyright (c) 2004 King Chung Huang

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
*/

#import "RMModelEditor.h"

#import "RMModel.h"
#import "Rule.h"
#import "Assignment.h"
#import "DMToolbarUtils.h"
#import "RMFilteringArrayController.h"
#import "EOControl.h"
#import "RMCompletionManager.h"
#import "RMTextFieldCell.h"
#import "RMTextField.h"
#import "RMTextView.h"
#import "RMComboBox.h"

@interface RMEnabledColorTransformer : NSValueTransformer {
}
@end

@implementation RMEnabledColorTransformer

+ (BOOL)allowsReverseTransformation {
    return NO;
}

- (id)transformedValue:(id)value {
    if ([value boolValue]) {
        return [NSColor textColor];
    } else {
        return [NSColor disabledControlTextColor];
    }    
}

@end

@interface RMModelEditor(Private)
- (void)updateLHSFormatting:(BOOL)formatted;
- (void)refreshAssignmentClassNamesComboBoxContents;
- (void)refreshRhsKeyNamesComboBoxContents;
- (void)refreshLhsKeyPathCompletionList;
- (void)refreshLhsStringValuesCompletionList;
- (void)refreshRhsStringValuesCompletionList;
- (NSNumber *)rhsValueIsNotMarker;
@end

@implementation RMModelEditor

+ (void)initialize {
	NSValueTransformer *colorTransformer = [[RMEnabledColorTransformer alloc] init];
    [NSValueTransformer setValueTransformer:colorTransformer forName:@"RMEnabledColorTransformer"];
	[colorTransformer release];
}

- (id)init {
    if (self = [self initWithWindowNibName:@"RMModelEditor"]) {
    }
    
    return self;
}

- (void)windowWillLoad {
    [super windowWillLoad];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.useParenthesesForComparisonQualifier" options:0 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.assignmentClassNames" options:0 context:NULL];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:@"values.rhsKeyPaths" options:0 context:NULL];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [[lhsFormatCheckbox cell] addObserver:self forKeyPath:@"state" options:0 context:NULL];
    [[lhsFormatCheckbox cell] setState:[[NSUserDefaults standardUserDefaults] boolForKey:@"formattedQualifier"] ? NSOnState:NSOffState];
}

- (void)setDocument:(NSDocument *)document {
    // We need to do that in order to avoid a KVO warning when document closes
    // Only that binding is problematic
    if(document == nil){
        [[self document] removeObserver:self forKeyPath:@"rules"];
        [rulesController unbind:@"contentArray"];
    }
    [super setDocument:document];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewFrameDidChangeNotification object:rhsValueHelpField];
	[toolbarItems autorelease];
    [rulesController removeObserver:self forKeyPath:@"selection.rhs.toolTip"];
    [rulesController removeObserver:self forKeyPath:@"selection.rhs.valueAsString"];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:@"values.useParenthesesForComparisonQualifier"];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:@"values.assignmentClassNames"];
    [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:@"values.rhsKeyPaths"];

    // The following two lines shouldn't be necessary, I think, but actually we need them, else an exception is raised
    [rhsValueTextView unbind:@"caseSensitivity"];
    [rhsValueTextView unbind:@"highlightedWords"];
    
    [[lhsFormatCheckbox cell] removeObserver:self forKeyPath:@"state"];

	[super dealloc]; // Will release all nib top-level objects
}

- (void)updateHelpViewSize {
    NSString    *toolTip = [rulesController valueForKeyPath:@"selection.rhs.toolTip"];
    NSRect      rhsValueTextViewFrame = [[rhsValueTextView enclosingScrollView] frame];
    NSRect      rhsValueHelpFieldFrame = [rhsValueHelpField frame];
    double      helpHeightIncrease;
    double      margin = 0;
    NSRect      invalidRect = NSUnionRect(rhsValueTextViewFrame, rhsValueHelpFieldFrame);
    
    if([toolTip isKindOfClass:[NSString class]]){
        NSRect  idealRect = rhsValueHelpFieldFrame;
        
        idealRect.size.height = 10000;
        idealRect.size = [[rhsValueHelpField cell] cellSizeForBounds:idealRect];
        
        helpHeightIncrease = idealRect.size.height - rhsValueHelpFieldFrame.size.height;
        if(rhsValueTextViewFrame.size.height - helpHeightIncrease < 56){
            helpHeightIncrease = rhsValueTextViewFrame.size.height - 56;
        }
        if(rhsValueHelpFieldFrame.size.height <= 2){
            margin = 9;
        }
    }
    else{
        if(rhsValueHelpFieldFrame.size.height > 2){
            margin = -9;
        }
        helpHeightIncrease = -rhsValueHelpFieldFrame.size.height + 1;
    }
    rhsValueTextViewFrame.origin.y += helpHeightIncrease + margin;
    rhsValueTextViewFrame.size.height -= helpHeightIncrease + margin;
    rhsValueHelpFieldFrame.size.height += helpHeightIncrease;
    [[rhsValueTextView enclosingScrollView] setFrame:rhsValueTextViewFrame];
    [rhsValueHelpField setPostsFrameChangedNotifications:NO];
    [rhsValueHelpField setFrame:rhsValueHelpFieldFrame];
    [rhsValueHelpField setPostsFrameChangedNotifications:YES];
    [[rhsValueHelpField superview] setNeedsDisplayInRect:invalidRect];
}

- (NSString *)actionNameWhenInserting:(BOOL)inserting ruleCount:(int)ruleCount {
    NSUndoManager   *um = [[self model] undoManager];
    NSString        *anActionNameFormat;
    
    if ((inserting && ![um isUndoing]) || (!inserting && [um isUndoing])) {
        if(ruleCount > 1)
            anActionNameFormat = NSLocalizedString(@"Insert %i Rules", @"Undo-redo action name");
        else
            anActionNameFormat = NSLocalizedString(@"Insert %i Rule", @"Undo-redo action name");
    }
    else{
        if(ruleCount > 1)
            anActionNameFormat = NSLocalizedString(@"Remove %i Rules", @"Undo-redo action name");
        else
            anActionNameFormat = NSLocalizedString(@"Remove %i Rule", @"Undo-redo action name");
    }
    
    return [NSString stringWithFormat:anActionNameFormat, ruleCount];
}

- (void) updateLHSFormatting:(BOOL)formatted {
    NSDictionary    *bindingInfo = [[lhsValueTextField infoForBinding:@"value"] retain];
    NSString        *aKeyPath = formatted ? @"selection.lhsFormattedDescription":@"selection.lhsDescription";
    
    [lhsValueTextField unbind:@"value"];
    [lhsValueTextField bind:@"value" toObject:[bindingInfo objectForKey:NSObservedObjectKey] withKeyPath:aKeyPath options:[bindingInfo objectForKey:NSOptionsKey]];
    [bindingInfo release];
}

- (void)beginMergeInsertUndos
{
    if(mergedRemoveIndexes == nil)
        mergedRemoveIndexes = [[NSMutableIndexSet indexSet] retain];
}

- (void)endMergeInsertUndos
{
    if(mergedRemoveIndexes == nil)
        return;

    // Issue the single undo message that will remove all inserted objects.
    [[[[self model] undoManager] prepareWithInvocationTarget:[self document]] removeRulesAtIndexes:mergedRemoveIndexes];
    [[[self model] undoManager] setActionName:[self actionNameWhenInserting:YES ruleCount:[mergedRemoveIndexes count]]];

    // Now that that's done, nullify the coalesced insert list.
    [mergedRemoveIndexes release];
    mergedRemoveIndexes = nil;
}

/*! @function   EnumerateRangesOfIndexSet
    @abstract   Returns the next contiguous range of the index set within the range *indexRangePointer.
    @discussion
    Provides a simple way to enumerate ranges of an NSIndexSet.  Enumeration has finished when the returned
    NSRange's length == 0.
 
    Note that this function works best when the indexes are expected to be adjacent thus forming ranges.
    When the indexes are more likely to be non-adjacent several ranges of length 1 will need to be output.
    Due to the desire to simplify the context (i.e. requiring only indexRangePointer for context) the
    algorithm is necessarily degenerate for this case.
 
    To fix this the API would have to accept a buffer of multiple NSRange structs that can be filled in.
    In that case there would be no degenerate case but the API would also be harder to use.
 */
static NSRange EnumerateRangesOfIndexSet(NSIndexSet *self, NSRangePointer indexRangePointer)
{
    // currentRange is what we're going to return.
    // Note that the initial location of the range really doesn't matter because a range of length 0
    // represents nothing regardless of where it starts.  That said, we reasonably expect upon second
    // and further calls that the start of indexRangePointer->location is going to be the first index
    // we find so it's a slight optimization so we hit the index == currentRange.location + currentRange.length
    // test by virtue of index == currentRange.location and currentRange.length == 0.
    NSRange currentRange = NSMakeRange(indexRangePointer != NULL ? indexRangePointer->location : 0, 0);

    NSUInteger rawIndexCount;
    static size_t const rawIndexBufferSize = 16;
    // Iterate over blocks of indexes.
    do {
        NSUInteger rawIndexBuffer[rawIndexBufferSize];
        rawIndexCount = [self getIndexes:rawIndexBuffer maxCount:rawIndexBufferSize inIndexRange:indexRangePointer];
        int i;
        // Iterate over indexes within a block.
        for(i=0; i < rawIndexCount; ++i)
        {
            NSUInteger const index = rawIndexBuffer[i];
            // If the index would logically extend the existing range then do so.
            if(index == currentRange.location + currentRange.length)
                ++currentRange.length;
            // If the index would not extend the current range and we have some items in the current
            // range then we need to stop iterating.  This is the degenerate case.
            else if(currentRange.length != 0)
            {
                if(indexRangePointer != NULL)
                {
                    // In most cases index (the new location) is going to be less than the ranges location
                    // because we have actually iterated too far and need to backtrack some.
                    // Extend the length by how much we're backtracking.
                    // Do this by first incrementing the range by location (thus making it an "end"
                    // rather than a location) then decrementing it by the new location.
                    indexRangePointer->length += indexRangePointer->location;
                    indexRangePointer->length -= index;
                    indexRangePointer->location = index;
                }
                return currentRange;
            }
            // Otherwise we hit the corner case where we started with the wrong range.
            else
            {
                currentRange.location = index;
                currentRange.length = 1;
            }
        } // end for loop over indexes within the block.
    } while(rawIndexCount >= rawIndexBufferSize);
    // If we get here we have finished iterating everything.  That does not mean currentRange.length == 0
    // however if you call again with the same context (the *indexRangePointer) there should be nothing
    // to iterate and currentRange.length will wind up staying == 0.
    return currentRange;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (object == [lhsFormatCheckbox cell]) {
        [self updateLHSFormatting:[[lhsFormatCheckbox cell] state] == NSOnState];
    }
    else if ([keyPath isEqualToString:@"selection.rhs.toolTip"])
        [self updateHelpViewSize];
    else if ([keyPath isEqualToString:@"selection.rhs.valueAsString"]){
        [self willChangeValueForKey:@"rhsValueIsNotMarker"];
        [self didChangeValueForKey:@"rhsValueIsNotMarker"];
    }
    else if ([keyPath isEqualToString:@"rules"]) {
        // Support for multiple window controllers:
        // we want to register the undo/redo only for the first controller.
        // We should probably move that code to RMModel.
        if([[[self document] windowControllers] objectAtIndex:0] == self){
            int aChangeKind = [[change objectForKey:NSKeyValueChangeKindKey] intValue];
            
            if (aChangeKind == NSKeyValueChangeInsertion) {
                NSIndexSet  *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
                if(mergedRemoveIndexes == nil)
                {
                    [[[[self model] undoManager] prepareWithInvocationTarget:[self document]] removeRulesAtIndexes:indexes];
                    [[[self model] undoManager] setActionName:[self actionNameWhenInserting:YES ruleCount:[indexes count]]];
                }
                else
                {
                    // Don't immediately issue the undo message to remove the objects.  Instead, keep track of what has
                    // been inserted.  We do that by merging all removeRulesAtIndexes: messages into one single message.
                    
                    // indexRange is context for the enumerator
                    NSRange indexRange = NSMakeRange(0, NSUIntegerMax);
                    
                    // currentRange is what we actually need to operate on.
                    NSRange currentRange;
                    
                    // Expectations:
                    // On older OS X releases we will supposedly see several individual inserts.  That means we'll be called
                    // several times each time only being able to enumerate a single range with a length of 1.
                    
                    // On newer OS X releases a block of objects will usually be inserted as one.  In this case we'll only
                    // be called once with a single range having a length of however many items were inserted.

                    // NOTE WELL: Due to the way we enumerate the index set (forming a single range for adjacent indexes
                    // but only being able to enumerate one range at a time) it is a supremely bad idea for this code
                    // to be called with an index set whose indexes are non-adjacent.
                    while( (currentRange = EnumerateRangesOfIndexSet(indexes, &indexRange)).length != 0)
                    {
                        [mergedRemoveIndexes shiftIndexesStartingAtIndex:currentRange.location by:currentRange.length];
                        [mergedRemoveIndexes addIndexesInRange:currentRange];
                    }
                }
            }
            else if(aChangeKind == NSKeyValueChangeRemoval){
                NSArray     *removedRules = [change objectForKey:NSKeyValueChangeOldKey];
                NSIndexSet  *indexes = [change objectForKey:NSKeyValueChangeIndexesKey];
                
                [[[[self model] undoManager] prepareWithInvocationTarget:[self document]] insertRules:removedRules atIndexes:indexes];
                [[[self model] undoManager] setActionName:[self actionNameWhenInserting:NO ruleCount:[removedRules count]]];
            }
        }
    }
    else if ([keyPath isEqualToString:@"values.useParenthesesForComparisonQualifier"]) {
        [[self rules] makeObjectsPerformSelector:@selector(resetDescriptionCaches)];
    }
    else if ([keyPath isEqualToString:@"values.assignmentClassNames"])
        [self refreshAssignmentClassNamesComboBoxContents];
    else if ([keyPath isEqualToString:@"values.rhsKeyPaths"])
        [self refreshRhsKeyNamesComboBoxContents];
}

- (void)helpViewFrameDidChange:(NSNotification *)notif {
    [self updateHelpViewSize];
}

- (NSArray *)rules {
    return [rulesController content];
}

- (void)refreshCompletionListNamed:(NSString *)completionListName fromRules:(NSArray *)rules keyPath:(NSString *)ruleKeyPath comboBox:(NSComboBox *)comboBox {
    NSMutableSet    *assignmentClassNamesSet = [NSMutableSet setWithArray:[rules valueForKeyPath:ruleKeyPath]];
    
    [[RMCompletionManager sharedManager] addWords:assignmentClassNamesSet toCompletionListNamed:completionListName];
    [comboBox reloadData];
}

- (void)refreshAssignmentClassNamesComboBoxContents {
    [self refreshCompletionListNamed:@"assignmentClassNames" fromRules:[self rules] keyPath:@"rhs.assignmentClass" comboBox:assignmentClassNamesComboBox];
}

- (void)refreshRhsKeyNamesComboBoxContents {
    [self refreshCompletionListNamed:@"rhsKeys" fromRules:[self rules] keyPath:@"rhs.keyPath" comboBox:rhsKeyNamesComboBox];
}

- (void)addToolbarItems {
    NSToolbarItem   *anItem;
    
	
//    addToolbarItem(toolbarItems, @"CopyForDocs", 
//                   NSLocalizedString(@"CopyForDocs", @"Toolbar item label"), 
//                   NSLocalizedString(@"Copy for Docs", @"Toolbar item palette label"), 
//                   NSLocalizedString(@"Copy in documentation form", @"Toolbar item tooltip"), 
//                   self, @selector(setImage:), [NSImage imageNamed:@"copyForDocumenting"], @selector(duplicate:), nil);
//	
    addToolbarItem(toolbarItems, @"NewRule", 
                   NSLocalizedString(@"New", @"Toolbar item label"), 
                   NSLocalizedString(@"New Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Add a new rule", @"Toolbar item tooltip"), 
                   self, @selector(setImage:), [NSImage imageNamed:@"new"], @selector(add:), nil);
    addToolbarItem(toolbarItems, @"DuplicateRule", 
                   NSLocalizedString(@"Duplicate", @"Toolbar item label"), 
                   NSLocalizedString(@"Duplicate Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Duplicate rules", @"Toolbar item tooltip"), 
                   self, @selector(setImage:), [NSImage imageNamed:@"duplicate"], @selector(duplicate:), nil);
    addToolbarItem(toolbarItems, @"RemoveRule", 
                   NSLocalizedString(@"Remove", @"Toolbar item label"), 
                   NSLocalizedString(@"Remove Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Remove rules", @"Toolbar item tooltip"), 
                   self, @selector(setImage:), [NSImage imageNamed:@"remove"], @selector(remove:), nil);
    anItem = addToolbarItem(toolbarItems, @"Filter", 
                            NSLocalizedString(@"Filter", @"Toolbar item label"), 
                            NSLocalizedString(@"Filter Rules", @"Toolbar item palette label"), 
                            NSLocalizedString(@"Enter a term or EOQualifier format", @"Toolbar item tooltip"), 
                            rulesController, @selector(setView:), filterView, @selector(search:), nil);
    [anItem setMaxSize:NSMakeSize(1000., [anItem maxSize].height)];
    [anItem setVisibilityPriority:NSToolbarItemVisibilityPriorityHigh];
    addToolbarItem(toolbarItems, @"PreviousRule", 
                   NSLocalizedString(@"Previous", @"Toolbar item label"), 
                   NSLocalizedString(@"Previous Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Select previous rule", @"Toolbar item tooltip"), 
                   rulesController, @selector(setImage:), [NSImage imageNamed:@"previous"], @selector(selectPrevious:), nil);
    addToolbarItem(toolbarItems, @"NextRule", 
                   NSLocalizedString(@"Next", @"Toolbar item label"), 
                   NSLocalizedString(@"Next Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Select next rule", @"Toolbar item tooltip"), 
                   rulesController, @selector(setImage:), [NSImage imageNamed:@"next"], @selector(selectNext:), nil);
    addToolbarItem(toolbarItems, @"PreviewRule", 
                   NSLocalizedString(@"Preview", @"Toolbar item label"), 
                   NSLocalizedString(@"Preview Rule", @"Toolbar item palette label"), 
                   NSLocalizedString(@"Toggle the source preview drawer", @"Toolbar item tooltip"), 
                   sourceDrawer, @selector(setImage:), [NSImage imageNamed:@"preview"], @selector(toggle:), nil);
}

- (BOOL)observesRules {
    return YES;
}

- (void)awakeFromNib {
    [[self window] useOptimizedDrawing:YES];
    
    NSSize  aSize = NSMakeSize(320, 120);
    aSize.height = [[NSUserDefaults standardUserDefaults] floatForKey:@"sourceDrawerHeight"];
    [sourceDrawer setContentSize:aSize];
    
    [rhsValueTextView setFieldEditor:YES]; // Thus, tab and return will end edition
    [rhsValueTextView setFocusRingType:NSFocusRingTypeExterior]; // FIXME No effect
    [[rhsValueTextView enclosingScrollView] setFocusRingType:NSFocusRingTypeExterior]; // FIXME No effect
    [rhsValueTextView setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]]; // Fixes error in nib
    [self updateHelpViewSize];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(helpViewFrameDidChange:) name:NSViewFrameDidChangeNotification object:rhsValueHelpField];
    [rulesController addObserver:self forKeyPath:@"selection.rhs.toolTip" options:0 context:NULL];
    [rulesController addObserver:self forKeyPath:@"selection.rhs.valueAsString" options:0 context:NULL];
    [rulesController setSortDescriptors:[NSArray arrayWithObjects:[[[NSSortDescriptor alloc] initWithKey:@"author" ascending:YES] autorelease], [[[NSSortDescriptor alloc] initWithKey:@"lhsDescription" ascending:YES] autorelease], [[[NSSortDescriptor alloc] initWithKey:@"rhs.keyPath" ascending:YES] autorelease], nil]];
    [rulesController rearrangeObjects];
    if ([self observesRules])
        [[self document] addObserver:self forKeyPath:@"rules" options:NSKeyValueObservingOptionOld context:NULL];
    [rulesTableView setCornerView:cornerView];
    [rulesTableView setAutosaveTableColumns:YES];
    
    toolbarItems = [[NSMutableDictionary dictionary] retain];
    [self addToolbarItems];    
    [self prepareToolbar];
    
    [self refreshAssignmentClassNamesComboBoxContents];
    [self refreshRhsKeyNamesComboBoxContents];
    [self refreshLhsKeyPathCompletionList];
    [self refreshLhsStringValuesCompletionList];
    [self refreshRhsStringValuesCompletionList];
    
    [lhsValueTextField bind:@"highlightsMatchingWords" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.highlightSearchFilterOccurences" options:nil];
    [lhsValueTextField bind:@"caseSensitivity" toObject:rulesController withKeyPath:@"searchIsCaseSensitive" options:nil];
    [lhsValueTextField bind:@"highlightColor" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.searchFilterHighlightColor" options:[NSDictionary dictionaryWithObject:@"NSUnarchiveFromData" forKey:NSValueTransformerNameBindingOption]];
    [lhsValueTextField bind:@"highlightedWords" toObject:rulesController withKeyPath:@"searchWords" options:nil];

    NSEnumerator    *anEnum = [[rulesTableView tableColumns] objectEnumerator];
    NSTableColumn   *aCol;
    
    while(aCol = [anEnum nextObject]){
        NSCell  *dataCell = [aCol dataCell];
        
        if([dataCell isKindOfClass:[RMTextFieldCell class]]){
            [dataCell setLineBreakMode:NSLineBreakByClipping];
            [dataCell setScrollable:YES];
        }
    }
    
    [rhsKeyNamesComboBox bind:@"highlightsMatchingWords" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.highlightSearchFilterOccurences" options:nil];
    [rhsKeyNamesComboBox bind:@"caseSensitivity" toObject:rulesController withKeyPath:@"searchIsCaseSensitive" options:nil];
    [rhsKeyNamesComboBox bind:@"highlightColor" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.searchFilterHighlightColor" options:[NSDictionary dictionaryWithObject:@"NSUnarchiveFromData" forKey:NSValueTransformerNameBindingOption]];
    [rhsKeyNamesComboBox bind:@"highlightedWords" toObject:rulesController withKeyPath:@"searchWords" options:nil];
    [rhsValueTextView bind:@"highlightsMatchingWords" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.highlightSearchFilterOccurences" options:nil];
    [rhsValueTextView bind:@"caseSensitivity" toObject:rulesController withKeyPath:@"searchIsCaseSensitive" options:nil];
    [rhsValueTextView bind:@"highlightColor" toObject:[NSUserDefaultsController sharedUserDefaultsController] withKeyPath:@"values.searchFilterHighlightColor" options:[NSDictionary dictionaryWithObject:@"NSUnarchiveFromData" forKey:NSValueTransformerNameBindingOption]];
    [rhsValueTextView bind:@"highlightedWords" toObject:rulesController withKeyPath:@"searchWords" options:nil];
}

- (NSString *)toolbarIdentifier {
    return @"DMWindowToolbar";
}

- (void) setFirstResponderInPart:(RMWindowPart)part {
    switch (part) {
        case RMWindowPriorityPart:
            [rulesTableView editColumn:[rulesTableView columnWithIdentifier:@"priority"] row:[rulesTableView selectedRow] withEvent:nil select:YES];
            break;
        case RMWindowLHSPart:
            [[self window] makeFirstResponder:lhsValueTextField];
            break;
        case RMWindowRHSClassPart:
            [[self window] makeFirstResponder:assignmentClassNamesComboBox];
            break;
        case RMWindowRHSKeyPathPart:
            [[self window] makeFirstResponder:rhsKeyNamesComboBox];
            break;
        case RMWindowRHSValuePart:
            [[self window] makeFirstResponder:rhsValueTextView];
            [rhsValueTextView selectAll:nil];
            break;            
    }
}

#pragma mark NSToolbar Methods

- (void)prepareToolbar {
    NSToolbar *toolbar = [[[NSToolbar alloc] initWithIdentifier:[self toolbarIdentifier]] autorelease];
    
    [toolbar setDelegate:self];
    [toolbar setAllowsUserCustomization:YES];
    [toolbar setAutosavesConfiguration:YES];
    [toolbar setDisplayMode:NSToolbarDisplayModeDefault];
    [toolbar setSizeMode:NSToolbarSizeModeDefault];
    
    [[self window] setToolbar:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *newItem = [[[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier] autorelease];
    NSToolbarItem *item = [toolbarItems objectForKey:itemIdentifier];
    
    [newItem setLabel:[item label]];
    [newItem setPaletteLabel:[item paletteLabel]];
    
    if ([item view] != NULL) {
        [newItem setView:[item view]];
        
        [newItem setMinSize:[item minSize]];
        [newItem setMaxSize:[item maxSize]];
    } else {
        [newItem setImage:[item image]];
    }
    
    [newItem setToolTip:[item toolTip]];
    [newItem setTarget:[item target]];
    [newItem setAction:[item action]];
    [newItem setMenuFormRepresentation:[item menuFormRepresentation]];
    [newItem setVisibilityPriority:[item visibilityPriority]];
    
    return newItem;
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    static NSArray *dii = nil;
    
    if (dii == nil) {
	dii = [[NSArray arrayWithObjects:@"NewRule", @"DuplicateRule", @"RemoveRule", NSToolbarSpaceItemIdentifier, @"PreviousRule", @"NextRule", NSToolbarSpaceItemIdentifier, @"PreviewRule", NSToolbarFlexibleSpaceItemIdentifier, @"Filter", nil] retain];
    }
    
    return dii;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    static NSArray *aii = nil;
    
    if (aii == nil) {
	aii = [[NSArray arrayWithObjects:@"NewRule", @"DuplicateRule", @"RemoveRule", @"PreviousRule", @"NextRule", @"PreviewRule", @"Filter", NSToolbarCustomizeToolbarItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier, NSToolbarSpaceItemIdentifier, NSToolbarSeparatorItemIdentifier, nil] retain];
    }
    
    return aii;
}

#pragma mark Stuff

- (RMModel *)model {
    return [self document];
}

- (IBAction)rhsComboBoxAction:(id)sender {
    NSString *name = [sender stringValue];
    
    if (sender == assignmentClassNamesComboBox) {
        [[RMCompletionManager sharedManager] addWord:name toCompletionListNamed:@"assignmentClassNames"];
        [sender reloadData];
    } else if (sender == rhsKeyNamesComboBox) {
        [[RMCompletionManager sharedManager] addWord:name toCompletionListNamed:@"rhsKeys"];
        [sender reloadData];
    }
}

//- (IBAction)copy:(id)sender {
//    NSResponder *firstResponder = [[self window] firstResponder];
//    if (firstResponder == rulesTableView) {
//		if ([rulesTableView numberOfSelectedRows] > 0) {
//			NSIndexSet *rowIdx = [rulesTableView selectedRowIndexes];
//			NSMutableArray *rows = [NSMutableArray arrayWithCapacity:[rulesTableView numberOfSelectedRows]];
//			
//			NSArray *rules = [rulesController arrangedObjects];
//			Rule *rule;
//			
//			NSUInteger idx = [rowIdx firstIndex];
//			
//			while (idx != NSNotFound) {
//				rule = [rules objectAtIndex:idx];
//				[rows addObject:rule];
//				
//				idx = [rowIdx indexGreaterThanIndex:idx];
//			}
//			
//			EOKeyValueArchiver *archiver = [[EOKeyValueArchiver alloc] init];
//			
//			[archiver encodeObject:rows forKey:@"rules"];
//			
//			NSDictionary *plist = [archiver dictionary];
//			
//			NSPasteboard *pb = [NSPasteboard generalPasteboard];
//			
//			[pb declareTypes:[NSArray arrayWithObjects:@"D2WRules", NSStringPboardType, nil] owner:nil];
//			NSAssert1([pb setPropertyList:plist forType:@"D2WRules"], @"Unable to set plist for D2WRules pboard type:\n%@", plist);
//			NSAssert1([pb setString:[plist description] forType:NSStringPboardType], @"Unable to set string for NSStringPboardType pboard type:\n%@", [plist description]);
//            [archiver release];
//		}
//    }
//}

- (IBAction)copy:(id)sender {
    [self copyForDocumenting:sender];
}

- (IBAction)copyForDocumenting:(id)sender;
{
    NSResponder *firstResponder = [[self window] firstResponder];
    if (firstResponder == rulesTableView) {
		if ([rulesTableView numberOfSelectedRows] > 0) {
			NSIndexSet *rowIdx = [rulesTableView selectedRowIndexes];
			
			NSArray *rules = [rulesController arrangedObjects];
			Rule *rule = nil;
			
			NSUInteger idx = [rowIdx firstIndex];
			
			NSPasteboard *pb = [NSPasteboard generalPasteboard];
			[pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:nil];
			NSMutableString *result = [NSMutableString stringWithCapacity:0];
			
			while (idx != NSNotFound) {
				if ([result length] > 0) {
					[result appendString:@"\n"];
				}
				rule = [rules objectAtIndex:idx];
				[result appendString:[rule description]];
				[pb setString:result forType:NSStringPboardType];
				
				idx = [rowIdx indexGreaterThanIndex:idx];
			}
			
		}
    }
}

- (IBAction)cut:(id)sender {
    [self copy:sender];
    [self remove:sender];
}


- (void)_optimizedAddRules:(NSArray *)rules
{
    // Paste optimization: insertion was fast, but undo was slow, because insertion was done one rule after the other
    // (that's Apple implementation of -[NSArrayController addObjects:]), thus removal undo was registered once per rule
    // (and undo/redo message was wrong).

    // Unfortunately it's not safe to do what this code was originally doing which is to turn off all observation of changes
    // to the document's rules array and fake an undo message.  The undo message must know the indexes of objects that will
    // be added to the underlying rules array and it's not possible to reliably calculate that because the array controller
    // can (and does) choose insertion points on its own.  The end result was that undoing something you added via this
    // method (i.e. paste or duplicate) would delete other rules.

    // As of at least 10.6 (and I suspect earlier than that) this is kind of a moot point because -[NSArrayController addObjects:]
    // does do only one insert.  So we really don't need to do this at all anymore except on older OS X versions.

    // Still, it can't hurt to at least attempt to support older versions.  With that in mind we change the API here to
    // notify the observer that we're about to potentially do a pile of inserts then notify the observer that we have finished
    // doing a pile of inserts.  The observer can then decide how it wishes to handle that.

    [(RMModelEditor *)[[[self document] windowControllers] objectAtIndex:0] beginMergeInsertUndos];
    [rulesController addObjects:rules];
    [(RMModelEditor *)[[[self document] windowControllers] objectAtIndex:0] endMergeInsertUndos];
}

//- (IBAction)paste:(id)sender {
//    NSResponder *firstResponder = [[self window] firstResponder];
//    
//    if (firstResponder == rulesTableView) {
//        NSPasteboard    *pb = [NSPasteboard generalPasteboard];
//        NSString        *type = [pb availableTypeFromArray:[NSArray arrayWithObject:@"D2WRules"]];
//        
//        if (type) {
//            NSDictionary    *plist = [pb propertyListForType:@"D2WRules"];	    
//            NSArray         *rules = [Rule rulesFromMutablePropertyList:plist];
//            
//            [self _optimizedAddRules:rules];
//        }
//    }
//}

- (IBAction)paste:(id)sender {
    NSResponder *firstResponder = [[self window] firstResponder];
    if (firstResponder == rulesTableView) {
        NSPasteboard    *pb = [NSPasteboard generalPasteboard];
        NSString        *type = [pb availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]];
        
        if (type) {
			NSString		*rulesString = [pb stringForType:NSStringPboardType];
            NSArray         *rules = [Rule rulesFromHumanlyReadableString:rulesString];

            [self _optimizedAddRules:rules];
        }
		// scroll to the last added row
		[rulesTableView scrollRowToVisible:[rulesTableView selectedRow]];
    }
}

- (IBAction)duplicate:(id)sender {
    NSResponder *firstResponder = [[self window] firstResponder];
    
    if (firstResponder == rulesTableView) {
	NSIndexSet *rowIdx = [rulesTableView selectedRowIndexes];
	NSMutableArray *rows = [NSMutableArray arrayWithCapacity:[rulesTableView numberOfSelectedRows]];
	
    NSArray *rules = [rulesController arrangedObjects];
	Rule *rule;
	
	NSUInteger idx = [rowIdx firstIndex];
	
	while (idx != NSNotFound) {
	    rule = [rules objectAtIndex:idx];
	    [rows addObject:[rule copy]];
	    
	    idx = [rowIdx indexGreaterThanIndex:idx];
	}
	
    [self _optimizedAddRules:rows];
    }
}

- (IBAction)add:(id)sender {
    [rulesController add:sender];
    // We need to delay the call to change the first responder, else it doesn't 
    // work when user uses menu or toolbar to create new rule
    [[lhsValueTextField window] performSelector:@selector(makeFirstResponder:) withObject:lhsValueTextField afterDelay:0];
}

- (IBAction)remove:(id)sender {
    [rulesController remove:sender];
}

- (IBAction)selectNext:(id)sender {
    [rulesController selectNext:sender];
}

- (IBAction)selectPrevious:(id)sender {
    [rulesController selectPrevious:sender];
}

- (IBAction)centerSelectionInVisibleArea:(id)sender {
    [self showSelectedRule:sender];
}

- (IBAction)showSelectedRule:(id)sender {
    [rulesTableView scrollRowToVisible:[rulesTableView selectedRow]];
}

- (BOOL)validateAction:(SEL)action {
    if ((action == @selector(copy:) || action == @selector(copyForDocumenting:) ||action == @selector(cut:) || action == @selector(duplicate:) || action == @selector(showSelectedRule:)) && [rulesTableView numberOfSelectedRows] == 0) {
	return NO;
    } else if (action == @selector(paste:)) {
	NSPasteboard *pb = [NSPasteboard generalPasteboard];
	//NSString *type = [pb availableTypeFromArray:[NSArray arrayWithObject:@"D2WRules"]];
	NSString *type = [pb availableTypeFromArray:[NSArray arrayWithObject:NSStringPboardType]];
	if (!type) {
	    return NO;
	}
//    } else if (action == @selector(duplicate:) && ([[self window] firstResponder] != rulesTableView || [rulesTableView numberOfSelectedRows] == 0)) {
//	return NO;
    } else if (action == @selector(remove:)) {
        return [rulesController canRemove];
    } else if (action == @selector(selectNext:)) {
	return [rulesController canSelectNext];
    } else if (action == @selector(selectPrevious:)) {
	return [rulesController canSelectPrevious];
    } else if (action == @selector(focus:)) {
        return [rulesController canFocus];
    } else if (action == @selector(unfocus:)) {
        return [rulesController canUnfocus];
    }
    
    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return [self validateAction:[item action]];
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)toolbarItem {
    return [self validateAction:[toolbarItem action]];
}

- (IBAction)focusFilter:(id)sender {
    [[[self window] toolbar] setVisible:YES];
    
    [[self window] makeFirstResponder:filterField];
}

- (NSSize)drawerWillResizeContents:(NSDrawer *)sender toSize:(NSSize)contentSize {
    if (sender == sourceDrawer)
        [[NSUserDefaults standardUserDefaults] setFloat:contentSize.height forKey:@"sourceDrawerHeight"];
    
    return contentSize;
}

- (void)restoreRules:(NSArray *)rules atIndexes:(NSIndexSet *)indexes {
    NSMutableArray  *modelRules = [[self rules] mutableCopy];
    NSUndoManager   *um = [[self document] undoManager];
    
    [[um prepareWithInvocationTarget:self] removeDuplicateRulesAtIndexes:indexes];
    [um setActionName:[NSString stringWithFormat:([indexes count] > 1 ? NSLocalizedString(@"Delete %i Duplicate Rule(s)", @"Undo-redo action name") : NSLocalizedString(@"Delete %i Duplicate Rule", @"Undo-redo action name")), [indexes count]]];
    [modelRules insertObjects:rules atIndexes:indexes];
    [(RMModel *)[self document] setRules:modelRules];
    [modelRules release];
}

- (void)removeDuplicateRulesAtIndexes:(NSIndexSet *)indexes {    
    NSMutableArray  *modelRules = [[self rules] mutableCopy];
    NSArray         *removedRules = [modelRules objectsAtIndexes:indexes];
    NSUndoManager   *um = [[self document] undoManager];
    
    [[um prepareWithInvocationTarget:self] restoreRules:removedRules atIndexes:indexes];
    [um setActionName:[NSString stringWithFormat:@"Delete %i Duplicate Rule(s)", [indexes count]]];
    [modelRules removeObjectsAtIndexes:indexes];
    [(RMModel *)[self document] setRules:modelRules];
    [modelRules release];
}

- (NSIndexSet *)duplicateRulesIndexes {
    NSMutableIndexSet   *duplicateRuleIndexes = [[NSMutableIndexSet alloc] init];
    NSArray             *allRules = [self rules];
    NSUInteger        i, j, count = [allRules count];
    
    for (i = 0; i < count; i++) {
        if (![duplicateRuleIndexes containsIndex:i]) {
            Rule    *eachRule = [allRules objectAtIndex:i];
            
            for (j = i + 1; j < count; j++) {
                Rule    *anotherRule = [allRules objectAtIndex:j];
                
                if ([eachRule isEqualToRule:anotherRule]) {
                    [duplicateRuleIndexes addIndex:j];
                }
            }
        }
    }
    
    return [duplicateRuleIndexes autorelease];
}

- (IBAction)removeDuplicateRules:(id)sender {
    NSIndexSet   *duplicateRuleIndexes = [self duplicateRulesIndexes];
    
    if ([duplicateRuleIndexes count] > 0) {
        // Test is necessary, else the arrayController would always add an entry to the undo stack, even when doing nothing!
        [self removeDuplicateRulesAtIndexes:duplicateRuleIndexes];
    }
}

- (IBAction)showDuplicateRules:(id)sender {
    NSIndexSet   *duplicateRuleIndexes = [self duplicateRulesIndexes];
    
    if ([duplicateRuleIndexes count] > 0) {
        // Test is necessary, else the arrayController would always add an entry to the undo stack, even when doing nothing!
        // We want to be sure user sees all duplicate entries, thus we reset the filtering and the focus
        [self showRules:[[self rules] objectsAtIndexes:duplicateRuleIndexes]];
    }
    else
        NSBeep();
}

- (void) showRules:(NSArray *)rules {
    [rulesController setFilterPredicate:nil];
    [rulesController unfocus:nil];
    [rulesController setSelectedObjects:rules]; // Uses -isEqual:!
    [rulesController focus:nil];
}

- (void)addToTableView:(NSTableView *)tableView {
    [self add:tableView];
}

- (RMFilteringArrayController *) rulesController {
    return rulesController;
}

- (IBAction)focus:(id)sender {
    [rulesController focus:sender];
}

- (IBAction)unfocus:(id)sender {
    [rulesController unfocus:sender];
}

- (NSNumber *)rhsValueIsNotMarker {
    return [NSNumber numberWithBool:!NSIsControllerMarker([rulesController valueForKeyPath:@"selection.rhs.valueAsString"])];
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    if([aCell isKindOfClass:[RMTextFieldCell class]]){
        // We can't use bindings for that, because tableView copies cells
        [aCell setHighlightedWords:[rulesController searchWords]];
        [aCell setCaseSensitivity:[rulesController searchIsCaseSensitive]];
        [aCell setHighlightColor:[[NSValueTransformer valueTransformerForName:@"NSUnarchiveFromData"] transformedValue:[[NSUserDefaults standardUserDefaults] objectForKey:@"searchFilterHighlightColor"]]];
        [aCell setHighlightsMatchingWords:[[NSUserDefaults standardUserDefaults] boolForKey:@"highlightSearchFilterOccurences"]];
    }
}

- (IBAction)openInNewWindow:(id)sender {
    [[(RMModel *)[self document] makeNewWindowController] showWindow:sender]; // Cast is not exact, but both RMModel and RMModelGroup have the same method
}

- (NSTableView	*) rulesTableView;
{
	return rulesTableView;
}

#pragma mark Completion for textView/textField
- (NSString *)completionListNameForObject:(id)control forStringValues:(BOOL)forStringValues {
    NSString    *completionListName = nil;    
    
    if(control == assignmentClassNamesComboBox)
        completionListName = @"assignmentClassNames";
    else if(control == rhsKeyNamesComboBox)
        completionListName = @"rhsKeys";
    else if(control == lhsValueTextField)
        completionListName = (forStringValues ? @"lhsStringValues":@"lhsKeyPaths");
    else if(control == rhsValueTextView)
        completionListName = @"rhsStringValues";
    else if(control == rulesTableView){
        NSString    *editedColumnIdentifier = [[[rulesTableView tableColumns] objectAtIndex:[rulesTableView editedColumn]] identifier];
        
        if ([editedColumnIdentifier isEqualToString:@"lhs"])
            completionListName = (forStringValues ? @"lhsStringValues":@"lhsKeyPaths");
        else if ([editedColumnIdentifier isEqualToString:@"rhs.value"])
            completionListName = @"rhsStringValues";
        else if ([editedColumnIdentifier isEqualToString:@"rhs.keyPath"])
            completionListName = @"rhsKeys";
//        else if ([editedColumnIdentifier isEqualToString:@"assignment"]) // Disabled, because we display class names with package in ()
//            completionListName = @"assignmentClassNames";
    }
    
    return completionListName;
}

// Also, invoke 'complete:' automatically (timer)? Option.
- (NSArray *)control:(NSControl *)control textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(int *)index {
    BOOL        isQuoted = charRange.location > 0 && [[textView string] characterAtIndex:charRange.location - 1] == '\'';
    NSString    *completionListName = [self completionListNameForObject:control forStringValues:isQuoted];
    
    if(completionListName != nil)
        return [[RMCompletionManager sharedManager] textView:textView completionsForPartialWordRange:charRange indexOfSelectedItem:index fromCompletionListNamed:completionListName];
    else
        return words;
}

- (NSArray *)textView:(NSTextView *)textView completions:(NSArray *)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(int *)index {
    BOOL        isQuoted = charRange.location > 0 && [[textView string] characterAtIndex:charRange.location - 1] == '"';
    NSString    *completionListName = [self completionListNameForObject:textView forStringValues:isQuoted];
    
    if(completionListName != nil)
        return [[RMCompletionManager sharedManager] textView:textView completionsForPartialWordRange:charRange indexOfSelectedItem:index fromCompletionListNamed:completionListName];
    else
        return words;
}

- (void)refreshCompletionListNamed:(NSString *)completionListName fromRules:(NSArray *)rules keyPath:(NSString *)ruleKeyPath {
    NSArray         *keyPaths = [rules valueForKeyPath:ruleKeyPath]; // Array of sets (+ NSNulls)
    NSMutableSet    *keyPathsSet = [NSMutableSet set];
    NSEnumerator    *anEnum = [keyPaths objectEnumerator];
    NSSet           *eachSet;
    
    while (eachSet = [anEnum nextObject]) {
        if (eachSet != (id)[NSNull null])
            [keyPathsSet unionSet:eachSet];
    }
    [[RMCompletionManager sharedManager] addWords:keyPathsSet toCompletionListNamed:completionListName];
}

- (void)refreshLhsKeyPathCompletionListFromRules:(NSArray *)rules {
    [self refreshCompletionListNamed:@"lhsKeyPaths" fromRules:rules keyPath:@"lhs.allKeyPaths"];
}

- (void)refreshLhsKeyPathCompletionList {
    [self refreshLhsKeyPathCompletionListFromRules:[self rules]];
}

- (void)refreshLhsStringValuesCompletionListFromRules:(NSArray *)rules {
    [self refreshCompletionListNamed:@"lhsStringValues" fromRules:rules keyPath:@"lhs.allStringValues"];
}

- (void)refreshLhsStringValuesCompletionList {
    [self refreshLhsStringValuesCompletionListFromRules:[self rules]];
}

// TODO Should be updated when lhs/rhs is modified!
- (void)refreshRhsStringValuesCompletionListFromRules:(NSArray *)rules {
    [self refreshCompletionListNamed:@"rhsStringValues" fromRules:rules keyPath:@"rhs.allStringValues"];
}

- (void)refreshRhsStringValuesCompletionList {
    [self refreshRhsStringValuesCompletionListFromRules:[self rules]];
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    NSArray *editedRules = [[self rulesController] selectedObjects];

    if ([aNotification object] == lhsValueTextField) {
        [self refreshLhsKeyPathCompletionListFromRules:editedRules];
        [self refreshLhsStringValuesCompletionListFromRules:editedRules];
    }
    else if ([aNotification object] == rulesTableView) {
        [self refreshLhsKeyPathCompletionListFromRules:editedRules];
        [self refreshLhsStringValuesCompletionListFromRules:editedRules];
        [self refreshRhsStringValuesCompletionListFromRules:editedRules];
        [self refreshCompletionListNamed:@"assignmentClassNames" fromRules:editedRules keyPath:@"rhs.assignmentClass" comboBox:assignmentClassNamesComboBox];
        [self refreshCompletionListNamed:@"rhsKeys" fromRules:editedRules keyPath:@"rhs.keyPath" comboBox:rhsKeyNamesComboBox];
    }
}

- (void)textDidEndEditing:(NSNotification *)aNotification {
    if ([aNotification object] == rhsValueTextView) {
        [self refreshRhsStringValuesCompletionListFromRules:[[self rulesController] selectedObjects]];
    }
}

#pragma mark Splitview Delegate Methods

- (float)splitView:(NSSplitView *)sender constrainMinCoordinate:(float)proposedMin ofSubviewAt:(int)offset {
    if (sender == masterSplitView) {
		if (offset == 0) {
			return proposedMin + 180.0;
		} else {
			return proposedMin + 40.0;
		}
	} else if (sender == detailSplitView) {
		return 130.0;
    } else if (sender == lhsSplitView) {
		return 90.0;
    }
    
    return proposedMin;
}

- (float)splitView:(NSSplitView *)sender constrainMaxCoordinate:(float)proposedMax ofSubviewAt:(int)offset {
    if (sender == masterSplitView) {
		if (offset == 0) {
			return proposedMax - 40;
		} else {
			return proposedMax - 180;
		}
    } else if (sender == lhsSplitView) {
		return proposedMax - 25.0;
    } else if (sender == detailSplitView) {
		return proposedMax - 180.0;
    }
    
    return proposedMax;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview {
    return YES;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)aNotification {
    [self updateHelpViewSize];
}

#pragma mark Combobox datasource methods

- (int)numberOfItemsInComboBox:(NSComboBox *)combobox {
    NSString    *completionListName = [self completionListNameForObject:combobox forStringValues:NO];
    
    if(completionListName)
        return [[[RMCompletionManager sharedManager] completionsInCompletionListNamed:completionListName] count];
    else
        return 0;
}

- (id)comboBox:(NSComboBox *)combobox objectValueForItemAtIndex:(int)index {
    NSString    *completionListName = [self completionListNameForObject:combobox forStringValues:NO];
    
    if(completionListName)
        return [[[RMCompletionManager sharedManager] completionsInCompletionListNamed:completionListName] objectAtIndex:index];
    else
        return nil;
}

- (NSString *)comboBox:(NSComboBox *)combobox completedString:(NSString *)string {
    NSString    *completionListName = [self completionListNameForObject:combobox forStringValues:NO];
    
    if(completionListName)
        return [[RMCompletionManager sharedManager] completedString:string fromCompletionListNamed:completionListName];
    else
        return string;
}

- (unsigned int)comboBox:(NSComboBox *)combobox indexOfItemWithStringValue:(NSString *)string {
    NSString    *completionListName = [self completionListNameForObject:combobox forStringValues:NO];
    
    if(completionListName)
        return [[[RMCompletionManager sharedManager] completionsInCompletionListNamed:completionListName] indexOfObject:string];
    else
        return NSNotFound;
}

@end
